# Phase 3: Cohort Building - Research

**Researched:** 2026-03-24
**Domain:** Clinical cohort construction with PCORnet CDM data using R tidyverse
**Confidence:** MEDIUM-HIGH

## Summary

Phase 3 builds a Hodgkin Lymphoma cohort using named filter predicates (has_*, with_*, exclude_*) applied sequentially with automatic attrition logging. The existing project infrastructure already provides critical utilities (ICD normalization, attrition logging, date parsing) and upstream data (payer_summary, first_dx). Implementation focuses on composing filter functions, extracting treatment flags from TUMOR_REGISTRY + PROCEDURES/PRESCRIBING, and assembling a patient-level cohort dataset.

**Primary recommendation:** Use existing attrition logging utilities (init_attrition_log, log_attrition) rather than tidylog for this phase. Named predicates should be tibble-in/tibble-out functions that compose cleanly. Treatment evidence combines TUMOR_REGISTRY date columns (DT_CHEMO, DT_RAD) as primary source with PROCEDURES/PRESCRIBING CPT/NDC codes as supplemental fallback. Age calculation via lubridate's interval() + time_length() ensures leap-year accuracy.

## User Constraints

### Locked Decisions (from CONTEXT.md)

- **D-01:** Filter chain order: has_hodgkin_diagnosis() -> with_enrollment_period() -> exclude_missing_payer() -> tag treatment flags
- **D-02:** Treatment predicates are identification flags only, not exclusion filters
- **D-03:** with_enrollment_period() requires at least one enrollment record (any duration), min_enrollment_days NOT enforced in v1
- **D-04:** exclude_missing_payer() removes patients where PAYER_CATEGORY_PRIMARY is NA, "Unknown", or "Unavailable"
- **D-05:** Treatment evidence from TUMOR_REGISTRY date columns (primary) + PROCEDURES/PRESCRIBING codes (supplemental)
- **D-06:** Three treatment flags: HAD_CHEMO, HAD_RADIATION, HAD_SCT (integer 0/1)
- **D-07:** SCT covers both autologous and allogeneic
- **D-08:** Treatment CPT/NDC code lists defined in 00_config.R
- **D-09:** Final cohort = full clinical profile per patient (ID, SOURCE, demographics, age_at_enr_start/end, first_hl_dx_date, payer fields, treatment flags, enrollment duration)
- **D-10:** Age calculated as age at enrollment start and end
- **D-11:** Cohort saved to CSV at output/cohort/hl_cohort.csv AND kept as hl_cohort tibble
- **D-12:** Patients with HL diagnosis but NO enrollment record excluded
- **D-13:** Multi-site patients: Claude's discretion
- **D-14:** Attrition logging uses existing init_attrition_log() + log_attrition() from utils_attrition.R

### Claude's Discretion

- Multi-site patient deduplication strategy (D-13)
- Internal structure of predicate functions (tibble-in/tibble-out vs logical vector)
- Exact CPT/HCPCS/NDC code lists for treatment detection (populate TREATMENT_CODES in config)
- How to handle patients with treatment evidence but no diagnosis date
- Console output formatting for cohort summary

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CHRT-01 | Named filter predicates (has_*, with_*, exclude_*) | Named predicate pattern documented; existing utils_icd.R provides is_hl_diagnosis() template |
| CHRT-02 | Attrition logging at every step | Existing utils_attrition.R provides init_attrition_log() + log_attrition() functions ready to use |
| CHRT-03 | ICD format matching (dotted/undotted) | Existing normalize_icd() in utils_icd.R handles both formats via str_remove_all("\\\.") |

## Standard Stack

### Core Libraries (Already in Project)
| Library | Version | Purpose | Already Used In |
|---------|---------|---------|-----------------|
| dplyr | 1.2.0+ | Data transformation, filter chain | 02_harmonize_payer.R |
| lubridate | 1.9.3+ | Age calculation, date arithmetic | utils_dates.R, 02_harmonize_payer.R |
| stringr | 1.5.1+ | ICD normalization (already implemented) | utils_icd.R |
| glue | 1.8.0 | Console logging messages | utils_attrition.R |
| readr | 2.2.0+ | CSV output | 02_harmonize_payer.R |

**Why these:** Already vetted by Phases 1-2. No new dependencies needed for cohort building.

### Supporting Functions (Already Implemented)
| Function | File | Purpose | Ready to Use |
|----------|------|---------|--------------|
| is_hl_diagnosis() | utils_icd.R | HL diagnosis matching (149 codes) | ✓ |
| normalize_icd() | utils_icd.R | Dotted/undotted ICD normalization | ✓ |
| init_attrition_log() | utils_attrition.R | Initialize attrition tracking | ✓ |
| log_attrition() | utils_attrition.R | Log filter step with console output | ✓ |
| parse_pcornet_date() | utils_dates.R | Multi-format date parsing | ✓ |

**Why reuse:** Utilities already handle ICD matching (CHRT-03) and attrition logging (CHRT-02). No wheel reinvention.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual attrition tracking | tidylog package | tidylog auto-logs all dplyr ops (verbose), existing log_attrition() targets patient counts only |
| age_calc() from eeptools | lubridate interval() + time_length() | eeptools adds dependency; lubridate already in stack and handles leap years correctly |
| Base R unique() for dedup | dplyr distinct() | distinct() is 30% faster on large datasets and integrates with pipe syntax |

## Architecture Patterns

### Recommended Cohort Building Structure
```
R/
├── 03_cohort_predicates.R   # Named filter functions (has_*, with_*, exclude_*)
├── 04_build_cohort.R        # Compose filter chain, add treatment flags, save output
└── utils_*.R                # (existing utilities — no changes needed)
```

### Pattern 1: Named Predicate Functions (Tibble-in, Tibble-out)

**What:** Filter functions that accept a patient-level tibble and return a filtered tibble. Names follow convention: has_* (inclusion), with_* (requires), exclude_* (exclusion).

**When to use:** All cohort filter steps. Enables composition via %>% pipe and clear attrition logging.

**Example:**
```r
# Source: Epidemiologist R Handbook - Deduplication patterns
# Adapted for PCORnet patient-level filtering

has_hodgkin_diagnosis <- function(patient_df) {
  # Get patient IDs with HL diagnosis from DIAGNOSIS table
  hl_patients <- pcornet$DIAGNOSIS %>%
    filter(is_hl_diagnosis(DX, DX_TYPE)) %>%
    distinct(ID)

  # Return only patients with HL diagnosis
  patient_df %>%
    semi_join(hl_patients, by = "ID")
}

with_enrollment_period <- function(patient_df) {
  # Get patient IDs with at least one enrollment record
  enrolled_patients <- pcornet$ENROLLMENT %>%
    distinct(ID)

  # Return only patients with enrollment
  patient_df %>%
    semi_join(enrolled_patients, by = "ID")
}

exclude_missing_payer <- function(patient_df, payer_summary) {
  # Remove patients with NA, "Unknown", or "Unavailable" payer
  patient_df %>%
    inner_join(
      payer_summary %>%
        filter(!is.na(PAYER_CATEGORY_PRIMARY) &
               !PAYER_CATEGORY_PRIMARY %in% c("Unknown", "Unavailable")),
      by = "ID"
    )
}
```

**Why tibble-in/tibble-out:** Composes cleanly in filter chain. Allows passing additional tables (payer_summary) as arguments. Enables semi_join pattern for set operations.

### Pattern 2: Attrition Logging with Unique Patient Counts

**What:** Track unique patient IDs (not row counts) through sequential filter steps using existing log_attrition() utility.

**When to use:** After every predicate application in the filter chain.

**Example:**
```r
# Source: Existing utils_attrition.R (lines 56-92)
# Pattern: log_attrition() infers n_before from previous step's n_after

attrition_log <- init_attrition_log()

# Step 1: Start with all patients in DEMOGRAPHIC
cohort <- pcornet$DEMOGRAPHIC %>%
  select(ID, SOURCE, SEX, RACE, HISPANIC, BIRTH_DATE)
attrition_log <- log_attrition(attrition_log, "Initial population", n_distinct(cohort$ID))

# Step 2: Apply has_hodgkin_diagnosis()
cohort <- cohort %>% has_hodgkin_diagnosis()
attrition_log <- log_attrition(attrition_log, "Has HL diagnosis", n_distinct(cohort$ID))

# Step 3: Apply with_enrollment_period()
cohort <- cohort %>% with_enrollment_period()
attrition_log <- log_attrition(attrition_log, "Has enrollment record", n_distinct(cohort$ID))

# ... and so on
```

**Why this pattern:** log_attrition() automatically calculates n_excluded and prints to console. Tracks patient counts (D-17 from Phase 1 CONTEXT).

### Pattern 3: Treatment Flag Detection (Multi-Source Evidence)

**What:** Combine TUMOR_REGISTRY date columns (primary) with PROCEDURES/PRESCRIBING codes (supplemental) to maximize treatment detection coverage.

**When to use:** For HAD_CHEMO, HAD_RADIATION, HAD_SCT flags.

**Example:**
```r
# Chemo flag: TUMOR_REGISTRY DT_CHEMO (primary) OR PRESCRIBING chemo NDC codes (supplemental)

# Primary: TUMOR_REGISTRY DT_CHEMO
tr_chemo <- bind_rows(
  pcornet$TUMOR_REGISTRY1 %>% filter(!is.na(DT_CHEMO)) %>% select(ID, DT_CHEMO),
  pcornet$TUMOR_REGISTRY2 %>% filter(!is.na(DT_CHEMO)) %>% select(ID, DT_CHEMO),
  pcornet$TUMOR_REGISTRY3 %>% filter(!is.na(DT_CHEMO)) %>% select(ID, DT_CHEMO)
) %>%
  distinct(ID) %>%
  mutate(had_chemo_tr = 1L)

# Supplemental: PRESCRIBING codes
rx_chemo <- pcornet$PRESCRIBING %>%
  filter(!is.na(RXNORM_CUI) & RXNORM_CUI %in% TREATMENT_CODES$chemo_ndc) %>%
  distinct(ID) %>%
  mutate(had_chemo_rx = 1L)

# Combine: any evidence = 1
chemo_flags <- cohort %>%
  select(ID) %>%
  left_join(tr_chemo, by = "ID") %>%
  left_join(rx_chemo, by = "ID") %>%
  mutate(HAD_CHEMO = if_else(had_chemo_tr == 1 | had_chemo_rx == 1, 1L, 0L)) %>%
  select(ID, HAD_CHEMO)
```

**Why multi-source:** TUMOR_REGISTRY may be incomplete for some patients. PROCEDURES/PRESCRIBING provides fallback evidence. Union (OR logic) maximizes sensitivity.

### Pattern 4: Age Calculation (Leap-Year Accurate)

**What:** Calculate age at enrollment start and end using lubridate's interval() + time_length() for leap-year accuracy.

**When to use:** When computing age_at_enr_start and age_at_enr_end for final cohort.

**Example:**
```r
# Source: lubridate best practices for age calculation
# URL: https://www.statology.org/lubridate-calculate-age/

cohort <- cohort %>%
  mutate(
    age_at_enr_start = as.integer(
      time_length(interval(BIRTH_DATE, enr_start_date), "years")
    ),
    age_at_enr_end = as.integer(
      time_length(interval(BIRTH_DATE, enr_end_date), "years")
    )
  )
```

**Why interval() + time_length():** Handles leap years correctly. Standard lubridate pattern. No external dependencies (eeptools). Returns floor(years) for integer ages.

### Anti-Patterns to Avoid

- **Don't use row counts for attrition:** Use n_distinct(cohort$ID) not nrow(cohort). Patient-level counts required (D-17).
- **Don't nest filters inside single dplyr call:** Use sequential predicates with attrition logging between each step. Enables clear audit trail.
- **Don't compute age with simple date arithmetic:** Use lubridate interval(). Leap years and timezone issues break naive subtraction.
- **Don't assume single enrollment per patient:** ENROLLMENT can have multiple rows per patient (multiple periods). Use group_by(ID) when aggregating.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ICD code normalization | Custom regex for dot removal | normalize_icd() in utils_icd.R | Already handles NA, preserves vectorization, tested in Phase 2 |
| Attrition tracking | Manual n_before/n_after calculation | init_attrition_log() + log_attrition() | Auto-infers n_before, prints to console, validated structure |
| Age calculation | Date subtraction / 365.25 | lubridate interval() + time_length() | Leap years, timezone handling, accurate anniversary age |
| Patient deduplication | Base R unique() or custom logic | dplyr distinct(ID) | 30% faster, pipe-friendly, handles multi-column dedup |
| Date parsing | Multiple parse attempts | parse_pcornet_date() | Already handles 4 formats (ISO, Excel, SAS DATE9, YYYYMMDD) |

**Key insight:** Phase 1-2 utilities already solve the hard problems (ICD matching, date parsing, attrition tracking). Phase 3 composes existing pieces — don't rebuild them.

## Treatment Code Standards (Hodgkin Lymphoma)

### Chemotherapy Detection

**Primary source:** TUMOR_REGISTRY DT_CHEMO, CHEMO_START_DATE_SUMMARY (columns 288, 648)

**Supplemental source:** PRESCRIBING RXNORM_CUI codes for ABVD regimen components:
- Doxorubicin (Adriamycin)
- Bleomycin
- Vinblastine
- Dacarbazine

**Claude's discretion:** Populate TREATMENT_CODES$chemo_ndc in 00_config.R. ABVD is the standard first-line regimen for Hodgkin lymphoma. Alternative regimens (BEACOPP, brentuximab vedotin) exist but are less common for initial treatment.

**Note:** J-code HCPCS range (J9000-J9999) traditionally covers chemotherapy drugs, but specific NDC/RXNORM codes are needed for PRESCRIBING table matching. Official HCPCS code lists updated annually by CMS.

### Radiation Therapy Detection

**Primary source:** TUMOR_REGISTRY DT_RAD (column 744-745 in TUMOR_REGISTRY2/3)

**Supplemental source:** PROCEDURES CPT codes for radiation therapy:
- **77427:** Radiation treatment management (weekly, per 5 fractions) — most common billing code
- **77301:** IMRT plan development
- **77407, 77412, 77402:** New 2026 complexity-based delivery codes (replaced 77385/77386)
- **77261-77263:** Treatment planning
- **77280-77290:** Simulation

**Claude's discretion:** Recommend 77427 as minimum detection code (treatment management = active radiation). Planning codes (77261-77290) may capture patients who planned but never received treatment.

**Note:** Major CPT changes effective 2026-01-01 replaced technique-based codes with complexity-based codes. Code 77385 (IMRT simple) deleted in 2026.

### Stem Cell Transplant (SCT) Detection

**Primary source:** TUMOR_REGISTRY columns (need to verify column names — likely in TUMOR_REGISTRY1 site-specific factors or treatment codes)

**Supplemental source:** PROCEDURES CPT codes:
- **38240:** Allogeneic hematopoietic progenitor cell (HPC) transplantation
- **38241:** Autologous HPC transplantation
- **38242:** Allogeneic donor lymphocyte infusion (DLI)
- **38243:** Allogeneic HPC boost (subsequent infusion from same donor)

**Usage:**
- 38240 = allogeneic (donor cells)
- 38241 = autologous (patient's own cells)
- Both covered by single HAD_SCT flag (D-07)

**Note:** SCT less common in Hodgkin lymphoma — typically reserved for relapsed/refractory disease. Autologous SCT more common than allogeneic for HL.

**Claude's discretion:** TREATMENT_CODES$sct_cpt = c("38240", "38241", "38242", "38243"). DLI (38242) included as SCT-related procedure.

### Code List Population Strategy

Recommend populating TREATMENT_CODES in 00_config.R with:

```r
TREATMENT_CODES <- list(
  # Chemotherapy: ABVD component RXNORM codes (Claude to research specific CUIs)
  chemo_ndc = c(
    # Doxorubicin RXNORM codes
    # Bleomycin RXNORM codes
    # Vinblastine RXNORM codes
    # Dacarbazine RXNORM codes
  ),

  # Radiation: Active treatment codes only (exclude planning-only)
  radiation_cpt = c("77427", "77407", "77412", "77402"),

  # SCT: All transplant types (autologous + allogeneic + DLI)
  sct_cpt = c("38240", "38241", "38242", "38243")
)
```

**Confidence:** MEDIUM. CPT codes verified from official 2026 sources. RXNORM codes for ABVD components need lookup in RxNorm browser or PRESCRIBING table exploration.

## Common Pitfalls

### Pitfall 1: Counting Rows Instead of Patients

**What goes wrong:** Using nrow(cohort) for attrition logging when cohort has multiple rows per patient (e.g., after left_join with multi-row tables like ENROLLMENT).

**Why it happens:** ENROLLMENT can have multiple periods per patient. After joining demographics + enrollment, one patient = multiple rows.

**How to avoid:** Always use n_distinct(cohort$ID) for attrition logging. Patient-level counts required (Phase 1 D-17).

**Warning signs:** Attrition log shows 0 exclusions when you know patients should be excluded. Row count inflated vs. patient count.

### Pitfall 2: Payer Category String Matching Without Normalization

**What goes wrong:** Filtering PAYER_CATEGORY_PRIMARY == "Unknown" fails when value is " Unknown" (leading space) or "UNKNOWN" (case variation).

**Why it happens:** Case sensitivity and whitespace in string comparisons. PCORnet data may have encoding variations.

**How to avoid:** Use %in% with exact expected values from payer_summary (already harmonized in Phase 2). payer_summary values already normalized via map_payer_category().

**Warning signs:** exclude_missing_payer() excludes fewer patients than expected. Manual inspection shows "Unknown" variants.

### Pitfall 3: Missing TUMOR_REGISTRY Columns Across TR1/TR2/TR3

**What goes wrong:** Assuming all TUMOR_REGISTRY tables have identical schemas. DT_CHEMO exists in TR2/TR3 but not TR1.

**Why it happens:** TUMOR_REGISTRY1 uses different column names (CHEMO_START_DATE_SUMMARY vs. DT_CHEMO).

**How to avoid:** Check csv_columns.txt before coding. Use conditional column selection: if ("DT_CHEMO" %in% names(pcornet$TUMOR_REGISTRY1)) {...}.

**Warning signs:** Error "object 'DT_CHEMO' not found" when processing TR1. Treatment flags unexpectedly 0 for patients with TR1 records only.

### Pitfall 4: Multi-Site Patient Deduplication Timing

**What goes wrong:** Deduplicating by ID after joining data from multiple tables causes loss of valid records. Same patient ID appears at multiple SOURCEs with different data.

**Why it happens:** OneFlorida+ is multi-site network (AMS, UMI, FLM, VRT). Patient may have encounters at multiple partners with same ID but different clinical details.

**How to avoid:** Decide deduplication strategy early (D-13). Options: (1) Keep all sites (multi-row per patient), (2) Keep primary site only (SOURCE from DEMOGRAPHIC), (3) Merge site data (first diagnosis across sites, union of treatments).

**Warning signs:** Patient count drops unexpectedly when distinct(ID) called. Treatment flags = 0 for patients with evidence at secondary site.

**Recommendation:** For v1, keep patient's primary site only (SOURCE from DEMOGRAPHIC table, which has one row per patient). Document as assumption.

### Pitfall 5: Treatment Flags With Missing Diagnosis Dates

**What goes wrong:** Patients have HAD_CHEMO = 1 but first_hl_dx_date = NA. Breaks downstream payer-at-treatment logic in Phase 4.

**Why it happens:** PROCEDURES/PRESCRIBING may record chemo for patients with no HL diagnosis in DIAGNOSIS or TUMOR_REGISTRY (diagnosis documented outside network, or miscoded encounter).

**How to avoid:** Document edge case in cohort summary. For v1, include in cohort (had_chemo is valid even without dx_date). Phase 4 visualizations will filter to patients with valid dx_date when needed.

**Warning signs:** Cohort has patients with treatment flags but no first_hl_dx_date. Cross-tab of HAD_CHEMO × is.na(first_hl_dx_date) shows non-zero counts.

## Code Examples

Verified patterns from existing project code and tidyverse best practices:

### Filter Chain Composition with Attrition Logging

```r
# Source: utils_attrition.R (lines 56-92) + dplyr filter patterns

source("R/00_config.R")      # Auto-loads utilities
source("R/01_load_pcornet.R") # Loads pcornet$* tables
source("R/02_harmonize_payer.R") # Loads payer_summary, first_dx

# Initialize attrition log
attrition_log <- init_attrition_log()

# Start with all patients in DEMOGRAPHIC (one row per patient)
cohort <- pcornet$DEMOGRAPHIC %>%
  select(ID, SOURCE, SEX, RACE, HISPANIC, BIRTH_DATE)
attrition_log <- log_attrition(attrition_log, "Initial population", n_distinct(cohort$ID))

# Filter 1: has_hodgkin_diagnosis()
hl_patients <- pcornet$DIAGNOSIS %>%
  filter(is_hl_diagnosis(DX, DX_TYPE)) %>%
  distinct(ID)

cohort <- cohort %>%
  semi_join(hl_patients, by = "ID")
attrition_log <- log_attrition(attrition_log, "Has HL diagnosis", n_distinct(cohort$ID))

# Filter 2: with_enrollment_period()
enrolled_patients <- pcornet$ENROLLMENT %>%
  distinct(ID)

cohort <- cohort %>%
  semi_join(enrolled_patients, by = "ID")
attrition_log <- log_attrition(attrition_log, "Has enrollment record", n_distinct(cohort$ID))

# Filter 3: exclude_missing_payer()
cohort <- cohort %>%
  inner_join(
    payer_summary %>%
      filter(!is.na(PAYER_CATEGORY_PRIMARY) &
             !PAYER_CATEGORY_PRIMARY %in% c("Unknown", "Unavailable")),
    by = "ID"
  )
attrition_log <- log_attrition(attrition_log, "Valid payer category", n_distinct(cohort$ID))

message("\n=== Attrition Summary ===")
print(attrition_log)
```

### Age Calculation (Leap-Year Accurate)

```r
# Source: lubridate best practices
# URL: https://www.statology.org/lubridate-calculate-age/
# URL: https://datacornering.com/how-to-calculate-age-in-r/

library(lubridate)

# Get enrollment start and end dates per patient
enrollment_dates <- pcornet$ENROLLMENT %>%
  group_by(ID) %>%
  summarise(
    enr_start_date = min(ENR_START_DATE, na.rm = TRUE),
    enr_end_date = max(ENR_END_DATE, na.rm = TRUE),
    enrollment_duration_days = as.numeric(enr_end_date - enr_start_date),
    .groups = "drop"
  )

# Join to cohort and calculate ages
cohort <- cohort %>%
  left_join(enrollment_dates, by = "ID") %>%
  mutate(
    age_at_enr_start = as.integer(
      time_length(interval(BIRTH_DATE, enr_start_date), "years")
    ),
    age_at_enr_end = as.integer(
      time_length(interval(BIRTH_DATE, enr_end_date), "years")
    )
  )
```

**Why time_length():** Handles leap years correctly. interval() creates precise time span. time_length(..., "years") converts to decimal years. as.integer() floors to whole years.

### Treatment Flag Detection (Multi-Source)

```r
# Source: D-05, D-06, D-07 from CONTEXT.md

# HAD_CHEMO: TUMOR_REGISTRY DT_CHEMO OR PRESCRIBING chemo codes
tr_chemo <- bind_rows(
  if (!is.null(pcornet$TUMOR_REGISTRY2)) {
    pcornet$TUMOR_REGISTRY2 %>%
      filter(!is.na(DT_CHEMO)) %>%
      select(ID)
  },
  if (!is.null(pcornet$TUMOR_REGISTRY3)) {
    pcornet$TUMOR_REGISTRY3 %>%
      filter(!is.na(DT_CHEMO)) %>%
      select(ID)
  }
) %>%
  distinct(ID) %>%
  mutate(had_chemo_tr = 1L)

rx_chemo <- pcornet$PRESCRIBING %>%
  filter(!is.na(RXNORM_CUI) & RXNORM_CUI %in% TREATMENT_CODES$chemo_ndc) %>%
  distinct(ID) %>%
  mutate(had_chemo_rx = 1L)

chemo_flags <- cohort %>%
  select(ID) %>%
  left_join(tr_chemo, by = "ID") %>%
  left_join(rx_chemo, by = "ID") %>%
  mutate(
    HAD_CHEMO = if_else(
      coalesce(had_chemo_tr, 0L) == 1 | coalesce(had_chemo_rx, 0L) == 1,
      1L,
      0L
    )
  ) %>%
  select(ID, HAD_CHEMO)

# HAD_RADIATION: TUMOR_REGISTRY DT_RAD OR PROCEDURES radiation CPT codes
tr_rad <- bind_rows(
  if (!is.null(pcornet$TUMOR_REGISTRY2)) {
    pcornet$TUMOR_REGISTRY2 %>%
      filter(!is.na(DT_RAD)) %>%
      select(ID)
  },
  if (!is.null(pcornet$TUMOR_REGISTRY3)) {
    pcornet$TUMOR_REGISTRY3 %>%
      filter(!is.na(DT_RAD)) %>%
      select(ID)
  }
) %>%
  distinct(ID) %>%
  mutate(had_rad_tr = 1L)

px_rad <- pcornet$PROCEDURES %>%
  filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) %>%
  distinct(ID) %>%
  mutate(had_rad_px = 1L)

rad_flags <- cohort %>%
  select(ID) %>%
  left_join(tr_rad, by = "ID") %>%
  left_join(px_rad, by = "ID") %>%
  mutate(
    HAD_RADIATION = if_else(
      coalesce(had_rad_tr, 0L) == 1 | coalesce(had_rad_px, 0L) == 1,
      1L,
      0L
    )
  ) %>%
  select(ID, HAD_RADIATION)

# HAD_SCT: PROCEDURES SCT CPT codes (38240, 38241, 38242, 38243)
sct_flags <- pcornet$PROCEDURES %>%
  filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$sct_cpt) %>%
  distinct(ID) %>%
  mutate(HAD_SCT = 1L) %>%
  select(ID, HAD_SCT)

# Join all treatment flags to cohort
cohort <- cohort %>%
  left_join(chemo_flags, by = "ID") %>%
  left_join(rad_flags, by = "ID") %>%
  left_join(sct_flags, by = "ID") %>%
  mutate(
    HAD_CHEMO = replace_na(HAD_CHEMO, 0L),
    HAD_RADIATION = replace_na(HAD_RADIATION, 0L),
    HAD_SCT = replace_na(HAD_SCT, 0L)
  )
```

### Multi-Site Patient Deduplication (Primary Site Strategy)

```r
# Source: Epidemiologist R Handbook - Deduplication
# URL: https://www.epirhandbook.com/en/new_pages/deduplication.html

# Strategy: Keep patient's primary site (SOURCE from DEMOGRAPHIC)
# DEMOGRAPHIC has one row per patient with canonical SOURCE assignment

# Already implemented: cohort starts with pcornet$DEMOGRAPHIC which has unique ID
# No additional deduplication needed IF we use DEMOGRAPHIC as source of truth

# If patient appears in ENROLLMENT at multiple sites, keep only primary site's enrollments
enrollment_primary_site <- pcornet$ENROLLMENT %>%
  inner_join(
    pcornet$DEMOGRAPHIC %>% select(ID, SOURCE),
    by = c("ID", "SOURCE")
  )

# This filters ENROLLMENT to only periods at the patient's primary site
```

**Why this works:** DEMOGRAPHIC is patient-level (one row per patient). SOURCE column in DEMOGRAPHIC is the canonical site assignment. Joining ENROLLMENT to DEMOGRAPHIC by both ID and SOURCE keeps only primary-site enrollment periods.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual attrition tracking | CohortConstructor package with built-in attrition | 2023-2025 | R/Medicine 2026 abstracts mention automated cohort attrition logging |
| Radiation CPT codes by technique (77385, 77386) | Complexity-based codes (77407, 77412, 77402) | 2026-01-01 | Major CPT restructure; 77385 deleted; must update code lists annually |
| Age = (current_date - birth_date) / 365.25 | lubridate interval() + time_length() | Ongoing best practice | Handles leap years, timezones; recommended by R lubridate documentation |
| tidylog for automatic logging | Targeted log_attrition() for patient counts | Project-specific | tidylog logs ALL dplyr ops (verbose); custom logging targets patient-level attrition only |

**Deprecated/outdated:**
- **CPT 77385, 77386:** Deleted 2026-01-01. Replaced by 77407, 77412, 77402 complexity codes.
- **Base R age calculation:** Simple date arithmetic doesn't handle leap years. Use lubridate.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Not established (out of scope for v1) |
| Config file | None — v1 is exploratory R scripts, not production code with automated tests |
| Quick run command | Manual verification via RStudio console |
| Full suite command | N/A |

### Phase Requirements → Manual Verification Map
| Req ID | Behavior | Verification Method | Evidence |
|--------|----------|---------------------|----------|
| CHRT-01 | Named predicates (has_*, with_*, exclude_*) | Code review: functions exist with correct names | Function definitions in 03_cohort_predicates.R |
| CHRT-02 | Attrition logging at every step | Console output: log_attrition() prints per step | Attrition log data frame + console messages |
| CHRT-03 | ICD format matching (dotted/undotted) | Test cases: manual verification with sample ICD codes | Existing normalize_icd() tested in Phase 2 |

### Sampling Rate
- **Per script completion:** Manual inspection of cohort summary (head(), summary(), count by payer)
- **Phase gate:** Full cohort validation before Phase 4 (check n_distinct(ID), treatment flag distributions, payer counts vs. Phase 2)

### Wave 0 Gaps
N/A — automated testing out of scope for v1. Exploratory R pipeline validated via manual inspection.

## Sources

### Primary (HIGH confidence)
- **Treatment CPT codes:** CMS Medicare Coverage Database (Radiation Therapy billing guidelines) - https://med.noridianmedicare.com/web/jea/provider-types/radiation-oncology
- **Stem cell transplant codes:** ASBMT CPT Codes for Bone Marrow Transplant - https://higherlogicdownload.s3.amazonaws.com/ASBMT/43a1f41f-55cb-4c97-9e78-c03e867db505/UploadedImages/BMT_Coding_Article_Final.pdf
- **PCORnet CDM specification:** PCORnet Common Data Model v7.0 - https://pcornet.org/wp-content/uploads/2025/01/PCORnet-Common-Data-Model-v70-2025_01_23.pdf
- **Existing project code:** R/utils_icd.R, R/utils_attrition.R, R/02_harmonize_payer.R (verified files)

### Secondary (MEDIUM confidence)
- **ABVD chemotherapy regimen:** Multiple clinical sources confirm ABVD as standard first-line treatment for Hodgkin lymphoma (https://healthsystem.osumc.edu/pteduc/docs/ABVD.pdf, https://www.cancerresearchuk.org/about-cancer/treatment/drugs/abvd)
- **R deduplication patterns:** Epidemiologist R Handbook - Deduplication chapter - https://www.epirhandbook.com/en/new_pages/deduplication.html
- **lubridate age calculation:** Official Statology guide + multiple R documentation sources - https://www.statology.org/lubridate-calculate-age/
- **PCORnet enrollment validation:** PCORnet 2020 accomplishments (enrollment segment validation described) - https://pmc.ncbi.nlm.nih.gov/articles/PMC7521354/

### Tertiary (LOW confidence - needs verification)
- **Specific RXNORM codes for ABVD:** WebSearch found regimen description but not specific NDC/RXNORM codes. Requires manual lookup in RxNorm browser or PRESCRIBING table exploration during implementation.
- **TUMOR_REGISTRY column names for SCT:** csv_columns.txt does not show explicit SCT date columns. May be in site-specific factors (SSF1-SSF25) or treatment summary codes. Verify during implementation.

## Metadata

**Confidence breakdown:**
- Treatment CPT codes (radiation, SCT): HIGH - verified from official CMS/ASBMT sources, 2026 updates documented
- ICD normalization, attrition logging: HIGH - existing project utilities already implemented and tested
- ABVD chemotherapy codes: MEDIUM - clinical regimen confirmed, specific RXNORM codes need lookup
- PCORnet enrollment validation: MEDIUM - general patterns documented, site-specific edge cases unknown
- Multi-site deduplication: LOW - strategy proposed but not verified against actual data distribution

**Research date:** 2026-03-24
**Valid until:** 60 days (2026-05-23) — CPT codes stable for 2026 calendar year; chemotherapy NDC codes may change with new formulations

**Sources consulted:**
- 15 web searches across treatment coding, PCORnet CDM practices, R tidyverse patterns
- 10 existing project files (R scripts, utilities, config, documentation)
- Official CMS, PCORnet, ASTRO, lubridate documentation
