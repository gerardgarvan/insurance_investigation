# Analytic Manual (AM): Mini Fixture

Data Ingest section header

## 1. Data Ingest & Change Log

| Event | Date | Notes |
|-------|------|-------|

## 3. Variable and Phenotype Decision Log

| Construct | Decision | Date |
|-----------|----------|------|

## 4. Data Cleaning and Harmonization Rules

### Cancer Diagnosis Date

- Expected fields listed here.

### Some Existing Domain

- Existing domain content.

<!-- BEGIN REPO-ONLY DOMAINS -->
### CBC {#S4-CBC}

#### Expected Structure

CBC events from LAB_RESULT_CM.

#### Observed Issues

None identified.

#### Cleaning Rules Applied

Use build_cbc_events().

#### Unresolved Issues

None.

### Single-Health-System Care (SHS) {#S4-SHS}

#### Expected Structure

Binary flag per patient.

#### Observed Issues

None identified.

#### Cleaning Rules Applied

Use R/169_single_source_care.R.

#### Unresolved Issues

None.

<!-- END REPO-ONLY DOMAINS -->

## 8. Open Questions and Decision Parking Lot

| Item | Notes | Date added |
|------|-------|------------|
| Manual: Claims as secondary source. Code: pipeline loads CDM only. Which should the manual record? | MISMATCH; D-191-01; S4-DXDT-01 | 2026-10-28 |
| OneFLquestions document location unknown | OPEN-DEPENDENCY; DEC-001 | 2026-10-27 |

## APPENDIX A. Embedded Working Tables

### A1. Data Ingest & Change Log

| Event | Date | Notes |
|-------|------|-------|

### A3. Variable and Phenotype Decision Log

| Construct | Decision | Date |
|-----------|----------|------|
