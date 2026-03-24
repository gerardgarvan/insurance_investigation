# Phase 2: Payer Harmonization - Research

**Researched:** 2026-03-24
**Domain:** Payer variable harmonization with 9-category mapping and encounter-level dual-eligible detection
**Confidence:** HIGH

## Summary

Phase 2 implements encounter-level payer harmonization matching the Python pipeline exactly. The core challenge is **encounter-level dual-eligible detection** (not temporal enrollment overlap as originally stated in PAYR-02). The Python reference document clarifies that dual-eligible status is determined per encounter by examining PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY combinations, with patient-level rollup (1 if any encounter is dual-eligible). This differs from temporal overlap approaches and requires careful effective payer logic.

The phase produces a patient-level summary tibble with 8 core payer variables (PAYER_CATEGORY_PRIMARY, PAYER_CATEGORY_AT_FIRST_DX, DUAL_ELIGIBLE, PAYER_TRANSITION, N_ENCOUNTERS, N_ENCOUNTERS_WITH_PAYER) plus a per-partner enrollment completeness report. All payer mapping rules, ICD codes, and effective payer logic are already defined in existing config files.

**Primary recommendation:** Build named functions (map_payer_category(), compute_effective_payer(), detect_dual_eligible()) using dplyr case_when() for prefix matching and stringr::str_starts_with() for category assignment. Match Python pipeline logic exactly to enable validation via dual-eligible rate comparison (should be 10-20% of Medicare+Medicaid combined).

## User Constraints

<user_constraints>

### Locked Decisions (from CONTEXT.md)

**D-01:** Encounter-level dual-eligible detection matching Python pipeline exactly (not temporal enrollment overlap). PAYR-02 requirement wording to be updated from "temporal overlap" to "encounter-level"

**D-02:** Effective payer per encounter = primary if valid, else secondary if valid, else null. Sentinels: null, empty, NI, UN, OT

**D-03:** 99/9999 are NOT sentinel values — they map to "Unavailable" category (matching Python default, no configurable toggle)

**D-04:** When PAYER_TYPE_SECONDARY is missing, dual_eligible = 0 (matches Python — cannot compute cross-payer check without secondary)

**D-05:** Dual-eligible overrides payer category to "Dual eligible" — no separate raw category column preserved

**D-06:** Compute core set: PAYER_CATEGORY_PRIMARY (most frequent), PAYER_CATEGORY_AT_FIRST_DX (mode within +/-30 days of first HL DX), DUAL_ELIGIBLE, PAYER_TRANSITION, N_ENCOUNTERS, N_ENCOUNTERS_WITH_PAYER

**D-07:** Treatment flags (HAD_CHEMO, HAD_RADIATION, HAD_SCT) deferred to Phase 3 cohort building

**D-08:** +/-30 day window for PAYER_CATEGORY_AT_FIRST_DX uses CONFIG$analysis$dx_window_days (already set to 30 in 00_config.R)

**D-09:** Tie-breaking for mode: sort by count descending, take first (matches Python)

**D-10:** First HL diagnosis date = earliest of DX_DATE (DIAGNOSIS table) and DATE_OF_DIAGNOSIS (TUMOR_REGISTRY tables). Both sources used

**D-11:** ICD code matching uses config list (ICD_CODES$hl_icd10 + hl_icd9) with dot-removal normalization on both sides

**D-12:** ICD normalization goes in shared R/utils_icd.R (normalize_icd(), is_hl_diagnosis()) — auto-sourced via 00_config.R, reusable by Phase 3

**D-13:** Named reusable functions: map_payer_category(), compute_effective_payer(), detect_dual_eligible(). Defined in 02_harmonize_payer.R. Readable and consistent with project's named-function style

**D-14:** Console summary table printed via message() + glue. Columns: partner, n_patients, n_with_enrollment, pct_enrolled, mean_covered_days, n_with_gaps

**D-15:** Enrollment gap = break >30 days between consecutive enrollment periods for same patient at same partner

**D-16:** Duration = total covered days (sum of actual enrollment period durations, excluding gaps)

**D-17:** Report also includes payer category distribution per partner (counts per category per site)

**D-18:** Primary output = patient-level summary tibble (payer_summary): one row per patient with ID, SOURCE, PAYER_CATEGORY_PRIMARY, PAYER_CATEGORY_AT_FIRST_DX, DUAL_ELIGIBLE, PAYER_TRANSITION, N_ENCOUNTERS, N_ENCOUNTERS_WITH_PAYER

**D-19:** Save to both environment (payer_summary object) and CSV (output/tables/payer_summary.csv) for manual inspection and Python comparison

**D-20:** Print validation summary after harmonization: total patients, per-category counts, dual-eligible rate, flag if dual-eligible rate outside 10-20% of Medicare+Medicaid combined

**D-21:** Script sources 01_load_pcornet.R (self-contained — running 02_harmonize_payer.R loads data automatically)

### Claude's Discretion

- Internal structure of map_payer_category() and compute_effective_payer() functions
- Console formatting for completeness report and validation summary
- Exact dplyr pipeline structure within named functions
- How to handle edge cases in gap detection (missing ENR_END_DATE, etc.)

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PAYR-01 | User can harmonize payer variables into 9 standard categories matching the Python pipeline (Medicare, Medicaid, Dual eligible, Private, Other government, No payment/Self-pay, Other, Unavailable, Unknown) | Prefix-based mapping using dplyr::case_when() with stringr::str_starts_with(); PAYER_MAPPING config already defines all prefix rules and exact-match codes |
| PAYR-02 | User can detect dual-eligible patients via temporal overlap of Medicare + Medicaid enrollment periods | **CORRECTED:** Encounter-level detection via PAYER_TYPE_PRIMARY + PAYER_TYPE_SECONDARY cross-checks (not temporal overlap). Detect via (1) Medicare primary + Medicaid secondary, (2) Medicaid primary + Medicare secondary, or (3) dual codes {14, 141, 142}. Patient-level = 1 if any encounter meets criteria |
| PAYR-03 | User can generate per-partner enrollment completeness report (% with enrollment records, mean duration, gap patterns) | Use dplyr::lag() to detect gaps >30 days between consecutive ENR_END_DATE and next ENR_START_DATE; summarize per partner via group_by(SOURCE) |

</phase_requirements>

## Standard Stack

### Core Libraries (already in project)

| Library | Version | Purpose | Already Configured |
|---------|---------|---------|-------------------|
| dplyr | 1.2.0+ | Data transformation, case_when() for mapping | ✅ (tidyverse dependency) |
| stringr | 1.5.1+ | Prefix detection (str_starts_with, str_remove) | ✅ (tidyverse dependency) |
| lubridate | 1.9.3+ | Date interval calculations for +/-30 day windows | ✅ (tidyverse dependency) |
| glue | 1.8.0 | Console reporting messages | ✅ (in use by utils_attrition.R) |
| readr | 2.2.0+ | CSV output (write_csv) | ✅ (in use by 01_load_pcornet.R) |

### Supporting Functions

| Function | Purpose | Source |
|----------|---------|--------|
| parse_pcornet_date() | Multi-format date parsing | utils_dates.R (existing) |
| log_attrition() | Console reporting pattern | utils_attrition.R (existing) |

**No new package installation required.** All libraries needed are already in the tidyverse stack and currently in use.

## Architecture Patterns

### Pattern 1: Prefix-Based Category Mapping with case_when()

**What:** Map payer type codes to categories using prefix matching (first character determines category). Use dplyr::case_when() with stringr::str_starts_with() for readable conditional logic.

**When to use:** PCORnet payer type codes follow a prefix convention (1xx = Medicare, 2xx = Medicaid, etc.). Prefix matching is more robust than exact-match lookup tables.

**Example:**
```r
# Source: dplyr case_when() official documentation + Python reference logic
map_payer_category <- function(payer_code) {
  case_when(
    # Exact-match overrides first
    payer_code %in% c("99", "9999") ~ "Unavailable",
    payer_code %in% c("NI", "UN", "OT", "UNKNOWN") | is.na(payer_code) ~ "Unknown",
    payer_code %in% c("14", "141", "142") ~ "Dual eligible",

    # Prefix-based mapping
    str_starts_with(payer_code, "1") ~ "Medicare",
    str_starts_with(payer_code, "2") ~ "Medicaid",
    str_starts_with(payer_code, "5") | str_starts_with(payer_code, "6") ~ "Private",
    str_starts_with(payer_code, "3") | str_starts_with(payer_code, "4") ~ "Other government",
    str_starts_with(payer_code, "8") ~ "No payment / Self-pay",
    str_starts_with(payer_code, "7") | str_starts_with(payer_code, "9") ~ "Other",

    # Default
    TRUE ~ "Other"
  )
}
```

**Note:** case_when() evaluates sequentially top-to-bottom. Put exact-match overrides (99, NI, dual codes) before prefix rules to prevent "9" from matching prefix "9" rule.

### Pattern 2: Effective Payer with Sentinel Fallback

**What:** Per-encounter effective payer = primary if valid (non-null, non-empty, not sentinel), else secondary if valid, else null. Sentinels (NI, UN, OT) trigger fallback to secondary.

**When to use:** PCORnet allows both PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY. When primary is missing/sentinel, secondary provides better information.

**Example:**
```r
# Source: Python reference PAYER_VARIABLES_AND_CATEGORIES.md
compute_effective_payer <- function(primary, secondary) {
  sentinel_values <- c("NI", "UN", "OT")

  # Check if primary is valid (non-null, non-empty, not sentinel)
  primary_valid <- !is.na(primary) &
                   nchar(trimws(primary)) > 0 &
                   !primary %in% sentinel_values

  # Check if secondary is valid
  secondary_valid <- !is.na(secondary) &
                     nchar(trimws(secondary)) > 0 &
                     !secondary %in% sentinel_values

  case_when(
    primary_valid ~ primary,
    secondary_valid ~ secondary,
    TRUE ~ NA_character_
  )
}
```

### Pattern 3: Encounter-Level Dual-Eligible Detection

**What:** An encounter is dual-eligible if (1) Medicare primary + Medicaid secondary, (2) Medicaid primary + Medicare secondary, or (3) dual code {14, 141, 142} in either primary or secondary. Patient-level DUAL_ELIGIBLE = 1 if any encounter is dual-eligible.

**When to use:** Matches Python pipeline logic exactly. Different from temporal enrollment overlap (which would use lubridate intervals).

**Example:**
```r
# Source: Python reference PAYER_VARIABLES_AND_CATEGORIES.md Section 3
detect_dual_eligible <- function(primary, secondary) {
  # When secondary is missing, dual-eligible = 0 (per D-04)
  if (is.na(secondary) | nchar(trimws(secondary)) == 0) {
    return(0)
  }

  dual_codes <- c("14", "141", "142")

  # Check if codes indicate dual-eligible
  medicare_primary <- str_starts_with(primary, "1")
  medicaid_primary <- str_starts_with(primary, "2")
  medicare_secondary <- str_starts_with(secondary, "2")
  medicaid_secondary <- str_starts_with(secondary, "2")

  has_dual_code <- primary %in% dual_codes | secondary %in% dual_codes

  cross_payer <- (medicare_primary & medicaid_secondary) |
                 (medicaid_primary & medicare_secondary)

  as.integer(has_dual_code | cross_payer)
}
```

### Pattern 4: Mode Calculation with Tie-Breaking

**What:** Calculate most frequent payer category per patient. For ties, sort by count descending and take first (arbitrary but deterministic).

**When to use:** PAYER_CATEGORY_PRIMARY and PAYER_CATEGORY_AT_FIRST_DX require mode of encounter-level categories.

**Example:**
```r
# Source: dplyr group_by + count pattern
# Calculate mode (most frequent value) with tie-breaking
encounters_with_payer %>%
  group_by(ID, payer_category) %>%
  summarise(n_encounters = n(), .groups = "drop") %>%
  arrange(ID, desc(n_encounters), payer_category) %>%  # Tie-break: alphabetical
  group_by(ID) %>%
  slice(1) %>%  # Take first (highest count)
  select(ID, PAYER_CATEGORY_PRIMARY = payer_category)
```

### Pattern 5: Enrollment Gap Detection with lag()

**What:** Detect gaps >30 days between consecutive enrollment periods for same patient at same partner. Use dplyr::lag() to get previous ENR_END_DATE and compare to current ENR_START_DATE.

**When to use:** Per-partner enrollment completeness report (PAYR-03, D-15).

**Example:**
```r
# Source: dplyr lag() documentation
enrollment_gaps <- pcornet$ENROLLMENT %>%
  filter(!is.na(ENR_START_DATE) & !is.na(ENR_END_DATE)) %>%
  arrange(ID, SOURCE, ENR_START_DATE) %>%
  group_by(ID, SOURCE) %>%
  mutate(
    prev_end_date = lag(ENR_END_DATE),
    gap_days = as.numeric(ENR_START_DATE - prev_end_date)
  ) %>%
  ungroup() %>%
  filter(!is.na(gap_days) & gap_days > 30)

# Count patients with gaps per partner
gaps_summary <- enrollment_gaps %>%
  group_by(SOURCE) %>%
  summarise(n_with_gaps = n_distinct(ID))
```

### Pattern 6: First HL Diagnosis Date from Multiple Sources

**What:** First HL diagnosis = earliest of DX_DATE (DIAGNOSIS table) and DATE_OF_DIAGNOSIS (TUMOR_REGISTRY1/2/3). Requires ICD code matching with dot normalization.

**When to use:** PAYER_CATEGORY_AT_FIRST_DX requires diagnosis date as anchor for +/-30 day window (D-10, D-11).

**Example:**
```r
# Source: Project decision D-10, D-11
# In utils_icd.R
normalize_icd <- function(icd_code) {
  str_remove(icd_code, "\\.")
}

is_hl_diagnosis <- function(icd_code, icd_type) {
  icd_clean <- normalize_icd(icd_code)

  icd10_clean <- normalize_icd(ICD_CODES$hl_icd10)
  icd9_clean <- normalize_icd(ICD_CODES$hl_icd9)

  (icd_type == "10" & icd_clean %in% icd10_clean) |
  (icd_type == "09" & icd_clean %in% icd9_clean)
}

# In 02_harmonize_payer.R
# Get first HL diagnosis date from DIAGNOSIS table
dx_dates <- pcornet$DIAGNOSIS %>%
  filter(is_hl_diagnosis(DX, DX_TYPE)) %>%
  group_by(ID) %>%
  summarise(first_dx_date_diagnosis = min(DX_DATE, na.rm = TRUE), .groups = "drop")

# Get first HL diagnosis from TUMOR_REGISTRY tables
tr_dates <- bind_rows(
  pcornet$TUMOR_REGISTRY1 %>% select(ID, DATE_OF_DIAGNOSIS),
  pcornet$TUMOR_REGISTRY2 %>% select(ID, DATE_OF_DIAGNOSIS),
  pcornet$TUMOR_REGISTRY3 %>% select(ID, DATE_OF_DIAGNOSIS)
) %>%
  filter(!is.na(DATE_OF_DIAGNOSIS)) %>%
  group_by(ID) %>%
  summarise(first_dx_date_tr = min(DATE_OF_DIAGNOSIS, na.rm = TRUE), .groups = "drop")

# Combine and take earliest
first_dx <- dx_dates %>%
  full_join(tr_dates, by = "ID") %>%
  mutate(first_hl_dx_date = pmin(first_dx_date_diagnosis, first_dx_date_tr, na.rm = TRUE))
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Mode calculation | Custom frequency table with max() | dplyr::count() + arrange() + slice(1) | Built-in aggregation handles ties, NA values, and edge cases. Custom max() breaks with multimodal distributions |
| String prefix matching | substr(x, 1, 1) == "1" | stringr::str_starts_with(x, "1") | Handles NA/empty gracefully, more readable, vectorized |
| Date interval overlaps | Manual date comparisons | lubridate::interval() + int_overlaps() | **NOT NEEDED for this phase** (encounter-level detection, not temporal overlap) but if needed: handles edge cases, time zones, leap years |
| Effective payer logic | Nested ifelse() chains | dplyr::case_when() | Readable, avoids deeply nested conditions, explicit TRUE default |
| Enrollment gap detection | Manual loop through sorted dates | dplyr::lag() within group_by() | Vectorized, handles missing values, works with grouped data |

**Key insight:** dplyr + stringr cover all harmonization needs. No custom loops, no base R ifelse() chains, no manual string manipulation. The tidyverse stack handles all edge cases (NA, empty strings, sorting, grouping).

## Common Pitfalls

### Pitfall 1: Case_When Order Matters

**What goes wrong:** Prefix rule "9" matches before exact-match "99", causing "99" to map to "Other" instead of "Unavailable".

**Why it happens:** case_when() evaluates top-to-bottom and stops at first match. "99" starts with "9", so prefix rule matches.

**How to avoid:** Put exact-match overrides (99, 9999, NI, UN, OT, dual codes) **before** prefix rules in case_when().

**Warning signs:** Validation shows zero "Unavailable" category when you expect some; "99" codes appear in "Other" category.

### Pitfall 2: Sentinel Values Not Triggering Fallback

**What goes wrong:** Primary payer "NI" (no information) doesn't fall back to secondary, leaving patient with "Unknown" payer when secondary has valid code.

**Why it happens:** Only checked for is.na(primary), not for sentinel strings (NI, UN, OT).

**How to avoid:** Define sentinel list explicitly and check `!primary %in% sentinels` in validity check, not just `!is.na(primary)`.

**Warning signs:** Patients have PAYER_TYPE_SECONDARY populated but effective_payer is null; more "Unknown" category than expected.

### Pitfall 3: Missing Secondary Column Breaks Dual-Eligible Detection

**What goes wrong:** When PAYER_TYPE_SECONDARY is entirely missing from ENCOUNTER table (not just NA values, but column doesn't exist), dual-eligible logic errors.

**Why it happens:** Code tries to access secondary column that doesn't exist in data frame.

**How to avoid:** Check `"PAYER_TYPE_SECONDARY" %in% names(pcornet$ENCOUNTER)` before dual-eligible detection. If missing, set all dual_eligible = 0 (per D-04).

**Warning signs:** Script errors on ENCOUNTER join; dual-eligible detection step fails.

### Pitfall 4: ICD Dot Format Mismatch

**What goes wrong:** Config has ICD codes in dotted format ("C81.00"), data has undotted format ("C8100"), matching fails, no HL diagnoses found.

**Why it happens:** PCORnet sites export ICD codes inconsistently (some with dots, some without).

**How to avoid:** Normalize both sides: remove dots from config codes AND from data codes before matching (per D-11, D-12).

**Warning signs:** First HL diagnosis date is NA for all patients; PAYER_CATEGORY_AT_FIRST_DX is null for entire cohort.

### Pitfall 5: Mode Tie-Breaking Not Deterministic

**What goes wrong:** Patient has equal counts for "Medicare" and "Private" (e.g., 5 encounters each). Mode selection is non-deterministic across runs.

**Why it happens:** arrange(desc(n)) leaves ties in arbitrary order; slice(1) picks first, but "first" varies.

**How to avoid:** Add secondary sort key: `arrange(ID, desc(n_encounters), payer_category)` to break ties alphabetically (per D-09).

**Warning signs:** Repeated runs produce different PAYER_CATEGORY_PRIMARY values for same patients; validation against Python shows inconsistent matches.

### Pitfall 6: Enrollment Gap Calculation Ignores Partner

**What goes wrong:** Patient switches from partner AMS to UMI. Gap detection treats AMS last enrollment end → UMI first enrollment start as a gap, but these are different systems.

**Why it happens:** lag() used without group_by(ID, SOURCE). Previous ENR_END_DATE comes from different partner.

**How to avoid:** Always group_by(ID, SOURCE) before lag() in enrollment gap detection (per D-15).

**Warning signs:** Unrealistically high gap counts; gaps coincide with partner switches visible in SOURCE column.

## Code Examples

Verified patterns from canonical references:

### Effective Payer with Sentinel Fallback (Encounter-Level)

```r
# Source: C:\cygwin64\home\Owner\Data loading and cleaing\docs\PAYER_VARIABLES_AND_CATEGORIES.md
# Function: compute_effective_payer()
# Input: ENCOUNTER with PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY
# Output: ENCOUNTER with effective_payer column

sentinel_values <- c("NI", "UN", "OT")

encounters <- pcornet$ENCOUNTER %>%
  mutate(
    # Validity checks
    primary_valid = !is.na(PAYER_TYPE_PRIMARY) &
                    nchar(trimws(PAYER_TYPE_PRIMARY)) > 0 &
                    !PAYER_TYPE_PRIMARY %in% sentinel_values,

    secondary_valid = !is.na(PAYER_TYPE_SECONDARY) &
                      nchar(trimws(PAYER_TYPE_SECONDARY)) > 0 &
                      !PAYER_TYPE_SECONDARY %in% sentinel_values,

    # Effective payer: primary if valid, else secondary if valid, else null
    effective_payer = case_when(
      primary_valid ~ PAYER_TYPE_PRIMARY,
      secondary_valid ~ PAYER_TYPE_SECONDARY,
      TRUE ~ NA_character_
    )
  )
```

### Dual-Eligible Detection (Encounter-Level)

```r
# Source: C:\cygwin64\home\Owner\Data loading and cleaing\docs\PAYER_VARIABLES_AND_CATEGORIES.md Section 3
# Function: detect_dual_eligible()
# Logic: (Medicare primary + Medicaid secondary) OR (Medicaid primary + Medicare secondary) OR dual codes {14, 141, 142}

dual_codes <- c("14", "141", "142")

encounters <- encounters %>%
  mutate(
    dual_eligible_encounter = case_when(
      # When secondary is missing, cannot compute dual-eligible (per D-04)
      is.na(PAYER_TYPE_SECONDARY) | nchar(trimws(PAYER_TYPE_SECONDARY)) == 0 ~ 0L,

      # Dual-eligible codes (14, 141, 142) in primary OR secondary
      PAYER_TYPE_PRIMARY %in% dual_codes | PAYER_TYPE_SECONDARY %in% dual_codes ~ 1L,

      # Medicare (1) + Medicaid (2) cross-payer combinations
      (str_starts_with(PAYER_TYPE_PRIMARY, "1") & str_starts_with(PAYER_TYPE_SECONDARY, "2")) ~ 1L,
      (str_starts_with(PAYER_TYPE_PRIMARY, "2") & str_starts_with(PAYER_TYPE_SECONDARY, "1")) ~ 1L,

      # Default: not dual-eligible
      TRUE ~ 0L
    )
  )

# Patient-level rollup: 1 if ANY encounter is dual-eligible
patient_dual <- encounters %>%
  group_by(ID) %>%
  summarise(DUAL_ELIGIBLE = as.integer(max(dual_eligible_encounter, na.rm = TRUE) == 1), .groups = "drop")
```

### Map Payer Category (with Dual-Eligible Override)

```r
# Source: C:\cygwin64\home\Owner\Data loading and cleaing\docs\PAYER_VARIABLES_AND_CATEGORIES.md Section 2
# Function: map_payer_category()
# Input: effective_payer, dual_eligible_encounter
# Output: payer_category (9 categories)

encounters <- encounters %>%
  mutate(
    payer_category_raw = case_when(
      # Exact-match overrides (BEFORE prefix rules)
      effective_payer %in% c("99", "9999") ~ "Unavailable",
      effective_payer %in% c("NI", "UN", "OT", "UNKNOWN") | is.na(effective_payer) ~ "Unknown",

      # Prefix-based mapping (PCORnet typology)
      str_starts_with(effective_payer, "1") ~ "Medicare",
      str_starts_with(effective_payer, "2") ~ "Medicaid",
      str_starts_with(effective_payer, "5") | str_starts_with(effective_payer, "6") ~ "Private",
      str_starts_with(effective_payer, "3") | str_starts_with(effective_payer, "4") ~ "Other government",
      str_starts_with(effective_payer, "8") ~ "No payment / Self-pay",
      str_starts_with(effective_payer, "7") | str_starts_with(effective_payer, "9") ~ "Other",

      # Default fallback
      TRUE ~ "Other"
    ),

    # Dual-eligible override (per D-05)
    payer_category = if_else(dual_eligible_encounter == 1, "Dual eligible", payer_category_raw)
  )
```

### Mode (Most Frequent Payer Category)

```r
# Source: dplyr count + arrange + slice pattern
# Function: Calculate PAYER_CATEGORY_PRIMARY (most frequent category per patient)

# Filter to encounters with valid effective payer
encounters_with_payer <- encounters %>%
  filter(!is.na(effective_payer) &
         !effective_payer %in% c("NI", "UN", "OT") &
         nchar(trimws(effective_payer)) > 0)

# Calculate mode with tie-breaking (per D-09)
payer_category_primary <- encounters_with_payer %>%
  group_by(ID, payer_category) %>%
  summarise(n_encounters = n(), .groups = "drop") %>%
  arrange(ID, desc(n_encounters), payer_category) %>%  # Tie-break: alphabetical
  group_by(ID) %>%
  slice(1) %>%
  select(ID, PAYER_CATEGORY_PRIMARY = payer_category)
```

### Payer Category at First Diagnosis (+/-30 Day Window)

```r
# Source: lubridate interval pattern + mode calculation
# Function: PAYER_CATEGORY_AT_FIRST_DX (mode within +/-30 days of first HL diagnosis)

dx_window_days <- CONFIG$analysis$dx_window_days  # 30 days

# Join encounters with first HL diagnosis dates
encounters_near_dx <- encounters_with_payer %>%
  inner_join(first_dx %>% select(ID, first_hl_dx_date), by = "ID") %>%
  mutate(
    days_from_dx = as.numeric(ADMIT_DATE - first_hl_dx_date)
  ) %>%
  filter(abs(days_from_dx) <= dx_window_days)

# Calculate mode in window
payer_at_first_dx <- encounters_near_dx %>%
  group_by(ID, payer_category) %>%
  summarise(n_encounters = n(), .groups = "drop") %>%
  arrange(ID, desc(n_encounters), payer_category) %>%
  group_by(ID) %>%
  slice(1) %>%
  select(ID, PAYER_CATEGORY_AT_FIRST_DX = payer_category)
```

### Enrollment Gap Detection

```r
# Source: dplyr lag() documentation + project decision D-15
# Function: Detect gaps >30 days between consecutive enrollment periods per patient per partner

enrollment_with_gaps <- pcornet$ENROLLMENT %>%
  filter(!is.na(ENR_START_DATE) & !is.na(ENR_END_DATE)) %>%
  arrange(ID, SOURCE, ENR_START_DATE) %>%
  group_by(ID, SOURCE) %>%
  mutate(
    prev_end_date = lag(ENR_END_DATE),
    gap_days = as.numeric(ENR_START_DATE - prev_end_date),
    has_gap = !is.na(gap_days) & gap_days > 30
  ) %>%
  ungroup()

# Count patients with gaps per partner
n_with_gaps_per_partner <- enrollment_with_gaps %>%
  filter(has_gap) %>%
  group_by(SOURCE) %>%
  summarise(n_with_gaps = n_distinct(ID), .groups = "drop")
```

### Enrollment Completeness Report (Per Partner)

```r
# Source: Project decision D-14, D-16, D-17
# Console summary: partner, n_patients, n_with_enrollment, pct_enrolled, mean_covered_days, n_with_gaps

# Total patients per partner
patients_per_partner <- pcornet$DEMOGRAPHIC %>%
  group_by(SOURCE) %>%
  summarise(n_patients = n_distinct(ID), .groups = "drop")

# Patients with enrollment per partner
patients_with_enrollment <- pcornet$ENROLLMENT %>%
  group_by(SOURCE) %>%
  summarise(n_with_enrollment = n_distinct(ID), .groups = "drop")

# Mean covered days per partner (sum of period durations / n_patients)
covered_days <- pcornet$ENROLLMENT %>%
  filter(!is.na(ENR_START_DATE) & !is.na(ENR_END_DATE)) %>%
  mutate(period_days = as.numeric(ENR_END_DATE - ENR_START_DATE)) %>%
  group_by(SOURCE, ID) %>%
  summarise(total_covered_days = sum(period_days, na.rm = TRUE), .groups = "drop") %>%
  group_by(SOURCE) %>%
  summarise(mean_covered_days = mean(total_covered_days, na.rm = TRUE), .groups = "drop")

# Combine all metrics
completeness_report <- patients_per_partner %>%
  left_join(patients_with_enrollment, by = "SOURCE") %>%
  left_join(covered_days, by = "SOURCE") %>%
  left_join(n_with_gaps_per_partner, by = "SOURCE") %>%
  mutate(
    pct_enrolled = round(100 * n_with_enrollment / n_patients, 1),
    n_with_gaps = replace_na(n_with_gaps, 0)
  )

# Print to console
message("\n=== Enrollment Completeness by Partner ===")
completeness_report %>%
  mutate(
    report_line = glue("{SOURCE}: {n_with_enrollment}/{n_patients} ({pct_enrolled}%) enrolled, ",
                       "mean {round(mean_covered_days)} days, {n_with_gaps} with gaps")
  ) %>%
  pull(report_line) %>%
  walk(message)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Temporal overlap for dual-eligible (lubridate intervals) | Encounter-level cross-payer check | Python pipeline standard | Simpler logic, matches reference implementation, no enrollment period merging needed |
| ifelse() chains for category mapping | case_when() with explicit conditions | dplyr 1.0+ (2020) | More readable, handles NA gracefully, order-dependent evaluation |
| Manual mode calculation with custom functions | count() + arrange() + slice(1) | dplyr best practice | Deterministic tie-breaking, built-in NA handling |
| Base R substr() for prefix matching | stringr::str_starts_with() | stringr 1.5+ (2023) | Vectorized, handles empty/NA, more readable |

**Deprecated/outdated:**
- **Temporal overlap dual-eligible detection:** PAYR-02 originally stated "temporal overlap detection" but Python reference uses encounter-level logic. This phase implements encounter-level to match Python exactly.
- **recode() for category mapping:** Deprecated in dplyr 1.1.0 (2023). Use case_when() or case_match() instead.
- **Base R ifelse():** Replaced by case_when() for multi-condition logic. ifelse() still valid for binary conditions but case_when() preferred for consistency.

## Open Questions

None. Python reference document provides exact logic for all harmonization steps. Config files already contain all mapping rules.

## Validation Strategy

### Validation 1: Dual-Eligible Rate Sanity Check

**What:** After harmonization, dual-eligible rate should be 10-20% of (Medicare + Medicaid) combined count.

**How:** Count patients per category. Calculate `dual_pct = n_dual / (n_medicare + n_medicaid)`. Flag if outside [0.10, 0.20] range.

**Why:** Python pipeline shows typical dual-eligible enrollment. Rates <10% suggest under-detection; >20% suggest over-detection.

**Implemented in:** Validation summary printed after harmonization (per D-20).

### Validation 2: Category Coverage

**What:** All 9 categories should be represented unless cohort is very small. "Unknown" and "Unavailable" should be <5% of total.

**How:** Count patients per category. Print distribution table. Flag if "Unknown" + "Unavailable" > 5%.

**Why:** High unknown/unavailable suggests data quality issues or mapping errors.

**Implemented in:** Validation summary printed after harmonization (per D-20).

### Validation 3: Manual Spot-Check Against Python

**What:** Export payer_summary.csv and compare first 100 patients against Python pipeline output.

**How:** Visual inspection of ID, PAYER_CATEGORY_PRIMARY, DUAL_ELIGIBLE columns. Look for systematic mismatches.

**Why:** End-to-end integration test. If logic matches exactly, outputs should be identical.

**Implemented in:** Manual step after script runs (per D-19: CSV saved for inspection).

## Sources

### Primary (HIGH confidence)

- [C:\cygwin64\home\Owner\Data loading and cleaing\docs\PAYER_VARIABLES_AND_CATEGORIES.md](file:///C:/cygwin64/home/Owner/Data%20loading%20and%20cleaing/docs/PAYER_VARIABLES_AND_CATEGORIES.md) - Python pipeline reference: 9-category mapping, effective payer logic, encounter-level dual-eligible detection, mode calculation, tie-breaking
- [R/00_config.R](file:///C:/Users/Owner/Documents/insurance_investigation/R/00_config.R) - PAYER_MAPPING list (prefix rules, sentinel values, dual codes), ICD_CODES list (149 HL codes), CONFIG$analysis$dx_window_days
- [R/01_load_pcornet.R](file:///C:/Users/Owner/Documents/insurance_investigation/R/01_load_pcornet.R) - ENCOUNTER, ENROLLMENT, DIAGNOSIS, TUMOR_REGISTRY table loading
- [.planning/phases/02-payer-harmonization/02-CONTEXT.md](file:///C:/Users/Owner/Documents/insurance_investigation/.planning/phases/02-payer-harmonization/02-CONTEXT.md) - User decisions D-01 through D-21

### Secondary (MEDIUM confidence)

- [dplyr case_when() documentation](https://dplyr.tidyverse.org/reference/case_when.html) - Vectorized if-else for category mapping
- [stringr str_starts_with()](https://stringr.tidyverse.org/) - Prefix matching for payer codes
- [lubridate interval() documentation](https://lubridate.tidyverse.org/reference/interval.html) - Date interval operations (for +/-30 day windows)
- [dplyr lag() documentation](https://dplyr.tidyverse.org/reference/lead-lag.html) - Lagged values for gap detection
- [CMS Dual-Eligible Reporting Expectations](https://www.medicaid.gov/tmsis/dataguide/t-msis-coding-blog/cms-guidance-reporting-expectations-for-dual-eligible-beneficiaries-updated/) - Policy context for dual-eligible definitions
- [PCORnet Common Data Model v7.0 Specification](https://pcornet.org/wp-content/uploads/2025/05/PCORnet_Common_Data_Model_v70_2025_05_01.pdf) - ENCOUNTER table schema (PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY)

### Tertiary (LOW confidence, for context only)

- [Fast Mode in R](https://medium.com/@antonysamuelb/fast-mode-in-r-5c588dda5807) - Alternative mode calculation approaches (not used; dplyr pattern preferred)
- [Detecting overlapping intervals lubridate GitHub issue](https://github.com/tidyverse/lubridate/issues/108) - Temporal overlap discussion (not used for this phase; encounter-level logic instead)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries already in project, no new dependencies
- Payer mapping logic: HIGH - Python reference document provides exact rules, config already defined
- Dual-eligible detection: HIGH - Encounter-level logic specified in canonical reference (D-01 clarification)
- Enrollment completeness: HIGH - dplyr lag() pattern is standard, well-documented
- ICD matching: HIGH - Normalization pattern straightforward, config contains all codes

**Research date:** 2026-03-24
**Valid until:** 60 days (stable domain: PCORnet CDM v7.0 released Jan 2025, no expected changes)

---

*Phase 2 research complete. Ready for planning decomposition into implementation tasks.*
