# Test Fixture Design

**Generated:** 2026-06-04
**Version:** 1.0
**Source:** tests/generate_fixtures.R

## Purpose

This document maps 20 synthetic patients (PT001-PT020) to 11 clinical edge cases, providing a complete specification for the PCORnet CDM test fixtures used in local testing. The fixtures enable verification of cohort filter predicates, payer harmonization logic, and treatment detection without HIPAA concerns.

## Patient Roster and Edge Case Mapping

| Patient ID | Edge Case(s) | Key Data | Expected Behavior |
|------------|--------------|----------|-------------------|
| PT001 | Baseline happy path | C81.10 ICD-10, payer 512 (private) | Passes all filters, included in final cohort |
| PT002 | Dual-eligible | Payer code "14" in ENCOUNTER | Maps to Medicaid; DUAL_ELIGIBLE = TRUE |
| PT003 | NLPHL | C81.00 diagnosis | Classified as NLPHL, not classical HL |
| PT004 | SCT | CPT 38241 in PROCEDURES | has_sct() = TRUE |
| PT005 | Multiple cancers | C81.40 (HL) + C50.911 (breast) | Both cancers in cancer summary |
| PT006 | Death date | DEATH_DATE = 2014-06-15 | Timeline truncated at death |
| PT007 | Orphan dx codes | Z51.11 without paired procedure | Flagged as orphan, not treatment evidence |
| PT008 | Same-day multi-payer | 2 encounters on 2013-07-10, payers "1" and "512" | Tiered payer resolution selects Medicare |
| PT009 | 1900 sentinel dates | ENR_START_DATE = 1900-01-01 | Filtered by exclude_1900_dates() |
| PT010 | ICD-9/ICD-10 cross-system | 201.90 on 2012-11-05 + C81.90 on 2012-11-15 (10-day gap) | Both codes contribute to 7-day gap confirmation |
| PT011 | Missing payer | PAYER_TYPE_PRIMARY = "NI" | Excluded by exclude_missing_payer() |
| PT012 | ABVD regimen | RXNORM_CUIs 3639, 11213, 67228, 3946 all on 2013-02-15 | Identified as ABVD first-line therapy |
| PT013 | Variation patient | C81.20 ICD-10, payer 111 (Medicare) | Standard flow, different payer category |
| PT014 | Variation patient | C81.30 ICD-10, payer 211 (Medicaid) | Standard flow, different payer category |
| PT015 | Variation patient | C81.40 ICD-10, payer 512 (private) | Standard flow, different HL subtype |
| PT016 | Variation patient | C81.70 ICD-10, payer 512 (private) | Standard flow, different HL subtype |
| PT017 | Variation patient | C81.90 ICD-10, payer 111 (Medicare) | Standard flow, unspecified HL |
| PT018 | Variation patient | C81.10 ICD-10, payer 211 (Medicaid) | Standard flow, baseline subtype |
| PT019 | Variation patient | C81.20 ICD-10, payer 512 (private) | Standard flow, additional coverage |
| PT020 | Baseline happy path #2 | C81.90 ICD-10, payer 512 (private) | Passes all filters; second baseline reference |

## Data Summary

| Table | Row Count | Key Features |
|-------|-----------|--------------|
| ENROLLMENT | 20 | One row per patient; PT009 has 1900 sentinel date |
| DIAGNOSIS | 18 | PT005 has 2 dx (HL + breast), PT007 has 2 dx (HL + Z51.11), PT010 has 2 dx (ICD-9 + ICD-10) |
| ENCOUNTER | 19 | PT005/PT007/PT008/PT010 have multiple encounters |
| DEMOGRAPHIC | 20 | One row per patient; ages 30-70 at diagnosis |
| PROCEDURES | 1 | PT004 SCT (CPT 38241) |
| PRESCRIBING | 4 | PT012 ABVD regimen (4 drugs) |
| DISPENSING | 0 | Empty (header only) - not used by current pipeline |
| MED_ADMIN | 0 | Empty (header only) - not used by current pipeline |
| CONDITION | 1 | Minimal (header + 1 row) - not actively filtered |
| LAB_RESULT_CM | 0 | Empty (header only) - surveillance lab values not tested in v1 |
| PROVIDER | 2 | Minimal (header + 2 rows) - provider specialty not filtered in v1 |
| DEATH | 1 | PT006 only |
| TUMOR_REGISTRY1 | 0 | Empty (header only) - HL diagnosis from DIAGNOSIS table sufficient |
| TUMOR_REGISTRY2 | 0 | Empty (header only) |
| TUMOR_REGISTRY3 | 0 | Empty (header only) |

## Edge Case Coverage Matrix

| Edge Case | Patient | Table(s) | Verification Query |
|-----------|---------|----------|-------------------|
| Dual-eligible | PT002 | ENCOUNTER | `filter(PAYER_TYPE_PRIMARY == "14")` |
| NLPHL | PT003 | DIAGNOSIS | `filter(DX == "C81.00")` |
| SCT | PT004 | PROCEDURES | `filter(PX == "38241")` |
| Multiple cancers | PT005 | DIAGNOSIS | `filter(ID == "PT005") %>% count()` returns 2 rows |
| Death date | PT006 | DEATH | `filter(ID == "PT006")` |
| Orphan dx | PT007 | DIAGNOSIS | `filter(DX == "Z51.11")` |
| Same-day multi-payer | PT008 | ENCOUNTER | `filter(ID == "PT008", ADMIT_DATE == "2013-07-10")` returns 2 rows |
| 1900 sentinel | PT009 | ENROLLMENT | `filter(ENR_START_DATE == "1900-01-01")` |
| ICD-9/ICD-10 cross | PT010 | DIAGNOSIS | `filter(ID == "PT010", DX_TYPE %in% c("09", "10"))` returns 2 rows |
| Missing payer | PT011 | ENCOUNTER | `filter(PAYER_TYPE_PRIMARY == "NI")` |
| ABVD regimen | PT012 | PRESCRIBING | `filter(ID == "PT012")` returns 4 rows with distinct RXNORM_CUIs |

## Verification Checklist

Before committing fixtures:

- [ ] All 15 CSVs present in tests/fixtures/
- [ ] Filename override correct: LAB_RESULT_Mailhot_V1.csv (not LAB_RESULT_CM_)
- [ ] Every table has SOURCE column
- [ ] Date columns are character strings (not Date objects)
- [ ] Patient IDs are zero-padded: PT001-PT020 (not PT1-PT20)
- [ ] Encounter IDs follow ENC{patient}_{seq} pattern
- [ ] Dual-eligible patient has payer code "14"
- [ ] ABVD patient has all 4 RXNORM_CUIs: 3639, 11213, 67228, 3946
- [ ] ICD-9/ICD-10 patient diagnoses are 7+ days apart
- [ ] Same-day multi-payer patient has 2 encounters with same ADMIT_DATE
- [ ] Total fixture size < 1MB for reasonable git performance
- [ ] CSVs are git-tracked (not in .gitignore)
- [ ] tests/generate_fixtures.R is git-tracked and runnable

## Regeneration Instructions

To update fixtures after editing design:

1. Edit `tests/generate_fixtures.R`
2. Run: `source("tests/generate_fixtures.R")`
3. Review generated CSVs in `tests/fixtures/`
4. Commit both script and CSVs: `git add tests/generate_fixtures.R tests/fixtures/*.csv`
5. Commit message: "fixtures: [description of change]"

## Technical Notes

### Payer Codes
- "14": Dual Eligibility Medicare/Medicaid (triggers DUAL_ELIGIBLE flag)
- "1": Medicare
- "111": Medicare Advantage
- "211": Medicaid
- "512": Commercial/Private
- "NI": No Information (filtered by exclude_missing_payer)

### ICD Codes
- C81.xx: ICD-10 Hodgkin Lymphoma (149 codes defined in R/00_config.R)
- 201.xx: ICD-9 Hodgkin Lymphoma (legacy codes)
- C81.00/C81.0x: Nodular lymphocyte predominant HL (NLPHL)
- Z51.11: Encounter for antineoplastic chemotherapy (orphan dx code without paired procedure)
- C50.911: Malignant neoplasm of breast (multiple cancer edge case)

### Treatment Codes
- CPT 38241: Autologous stem cell transplant
- RXNORM_CUI 3639: Doxorubicin (ABVD component)
- RXNORM_CUI 11213: Bleomycin (ABVD component)
- RXNORM_CUI 67228: Vinblastine (ABVD component)
- RXNORM_CUI 3946: Dacarbazine (ABVD component)

### Date Ranges
- Enrollment: 2010-2015 (covers diagnosis period)
- Diagnoses: 2012-2014 (centered on ICD-9/ICD-10 transition)
- Cross-system patient: 10-day gap (2012-11-05 to 2012-11-15) to satisfy 7-day unique gap rule

### OneFlorida+ Sites
- UFH: University of Florida Health
- AMS: (partner site code)
- FLM: Florida claims-only site
- VRT: (partner site code)
- UMI: University of Miami
