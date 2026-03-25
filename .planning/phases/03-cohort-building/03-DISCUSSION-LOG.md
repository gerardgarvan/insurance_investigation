# Phase 3: Cohort Building - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-03-24
**Phase:** 03-cohort-building
**Areas discussed:** Filter chain steps, Cohort output contents, Treatment flag extraction, Edge case handling

---

## Filter Chain Steps

| Option | Description | Selected |
|--------|-------------|----------|
| Just the 3 named | has_hodgkin_diagnosis, with_enrollment_period, exclude_missing_payer -- matches requirements exactly | |
| Add age/demographic filters | e.g., exclude_pediatric() or with_known_sex() | |
| Add site-specific filters | e.g., exclude_death_only_partner() to drop VRT | |

**User's choice:** Other -- "there should be filters for chemo, radiation, and stem cell therapy"
**Notes:** User wants treatment-specific predicates (has_chemo, has_radiation, has_sct) in addition to the 3 named predicates

---

### Treatment Predicate Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Identification flags | Tag each patient with HAD_CHEMO, HAD_RADIATION, HAD_SCT but keep all HL patients | ✓ |
| Inclusion filters | Only keep patients who had at least one treatment | |
| Both -- flag then filter | Flag all treatments, then apply exclude_untreated() | |

**User's choice:** Identification flags (Recommended)
**Notes:** All HL patients remain in cohort regardless of treatment status

---

### Filter Chain Order

| Option | Description | Selected |
|--------|-------------|----------|
| Diagnosis first | 1) has_hodgkin_diagnosis -> 2) with_enrollment_period -> 3) exclude_missing_payer -> tag treatments | ✓ |
| Enrollment first | 1) with_enrollment_period -> 2) has_hodgkin_diagnosis -> 3) exclude_missing_payer -> tag treatments | |
| You decide | Claude picks optimal order | |

**User's choice:** Diagnosis first (Recommended)
**Notes:** Clinical standard -- identify disease first, then validate enrollment

---

### Enrollment Validity

| Option | Description | Selected |
|--------|-------------|----------|
| Any enrollment record | Patient has at least one enrollment row -- simplest | ✓ |
| Minimum 30 days enrolled | Total covered days >= 30 | |
| Enrollment overlapping diagnosis | Must cover first HL diagnosis date | |

**User's choice:** Any enrollment record (Recommended)
**Notes:** CONFIG$analysis$min_enrollment_days stays in config for optional future use

---

## Cohort Output Contents

### Dataset Composition

| Option | Description | Selected |
|--------|-------------|----------|
| Full clinical profile | ID, SOURCE, demographics, first_hl_dx_date, payer fields, treatment flags, enrollment duration | ✓ |
| Minimal -- IDs + payer | ID, SOURCE, PAYER_CATEGORY_PRIMARY, DUAL_ELIGIBLE | |
| Payer + diagnosis only | ID, SOURCE, payer fields, first_hl_dx_date, ICD subtype | |

**User's choice:** Full clinical profile (Recommended)

---

### Output Format

| Option | Description | Selected |
|--------|-------------|----------|
| CSV to output/cohort/ | Save to output/cohort/hl_cohort.csv + keep in R environment | ✓ |
| Environment only | Keep hl_cohort tibble, no CSV | |
| Both CSV + RDS | CSV for inspection + RDS for faster reloading | |

**User's choice:** CSV to output/cohort/ (Recommended)

---

### Demographics

| Option | Description | Selected |
|--------|-------------|----------|
| As-is from DEMOGRAPHIC | Pull SEX, RACE, HISPANIC directly, calculate age from BIRTH_DATE | |
| Recode to readable labels | Map codes to human-readable labels | |

**User's choice:** Other -- "age can be calculated at age at start of enrollment and age at end of enrollment"
**Notes:** Two age columns (age_at_enr_start, age_at_enr_end), PCORnet codes stay as-is

---

## Treatment Flag Extraction

### Data Source

| Option | Description | Selected |
|--------|-------------|----------|
| TUMOR_REGISTRY only | DT_CHEMO, DT_RAD, DT_OTHER date presence check | |
| PROCEDURES + PRESCRIBING | CPT/HCPCS procedure codes and NDC drug codes | |
| Both sources combined | TUMOR_REGISTRY as primary, PROCEDURES/PRESCRIBING as supplement | ✓ |

**User's choice:** Both sources combined

---

### Code List Location

| Option | Description | Selected |
|--------|-------------|----------|
| In 00_config.R | TREATMENT_CODES list with chemo_cpt, radiation_cpt, sct_cpt, chemo_ndc vectors | ✓ |
| In predicate functions | Self-contained in has_chemo(), has_radiation(), has_sct() | |
| You decide | Claude picks | |

**User's choice:** In 00_config.R (Recommended)

---

### SCT Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Both auto + allo | Single HAD_SCT flag covering both types | ✓ |
| Separate flags | HAD_AUTO_SCT and HAD_ALLO_SCT as distinct | |
| You decide | Claude picks based on data | |

**User's choice:** Both auto + allo (Recommended)

---

## Edge Case Handling

### No Enrollment Record

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude with attrition log | with_enrollment_period() drops them, logged in waterfall | ✓ |
| Keep with NA enrollment | Include with NA fields, preserve all HL patients | |
| You decide | Claude picks | |

**User's choice:** Exclude with attrition log (Recommended)

---

### Multi-site Patients

| Option | Description | Selected |
|--------|-------------|----------|
| Keep all records, flag duplicates | One row per patient, earliest diagnosis across sites, add multi-site flag | |
| Deduplicate to single site | Keep only one record from site with most encounters | |
| You decide | Claude picks based on data exploration | ✓ |

**User's choice:** You decide
**Notes:** Deferred to Claude's discretion during implementation

---

### Missing Payer Definition

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude only NA | Drop NA, keep Unknown and Unavailable | |
| Exclude NA + Unknown + Unavailable | Drop all three, only concrete payer categories | ✓ |
| You decide | Claude picks | |

**User's choice:** Exclude NA + Unknown + Unavailable

---

## Claude's Discretion

- Multi-site patient deduplication strategy
- Internal structure of predicate functions
- Exact CPT/HCPCS/NDC code lists for treatment detection
- Console output formatting

## Deferred Ideas

None -- discussion stayed within phase scope
