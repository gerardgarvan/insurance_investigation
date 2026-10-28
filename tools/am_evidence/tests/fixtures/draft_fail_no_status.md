# AM-DRAFT
<!-- commit: abc1234 -->

## 1. Data Ingest & Change Log

| Event | Type | Date | Source | Notes | Map ID | Status | Cite |
|-------|------|------|--------|-------|--------|--------|------|
| PCORnet CDM extract received | RECEIVED | 2025-09-15 | OneFlorida+ | Mailhot HL cohort | SA1-LOG-01 | DRAFTED | R/00_config.R:DUCKDB_PATH:L1-L5 |
  STATUS: DRAFTED
  CITE: R/00_config.R:DUCKDB_PATH:L1-L5

## 3. Variable and Phenotype Decision Log

| Construct | Initial plan | Issue identified | Decision made | Rationale | Date | Affected analyses | Map ID | Status | Cite |
|-----------|-------------|-----------------|---------------|-----------|------|-------------------|--------|--------|------|
| CBC definition | Use LAB codes | None | Use build_cbc_events() | Repo implements this | 2026-10-01 | Phase 165 | SA3-DEC-01 | DRAFTED | R/utils/utils_distance_cbc.R:build_cbc_events():L20-L58 |
  STATUS: DRAFTED
  CITE: R/utils/utils_distance_cbc.R:build_cbc_events():L20-L58

## 4. Data Cleaning and Harmonization Rules

### Cancer Diagnosis Date

- [S4-DXDT-01] ICD codes drive cancer diagnosis date assignment.
  CITE: R/00_config.R:CANCER_CODES:L1-L5

<!-- BEGIN REPO-ONLY DOMAINS -->
### CBC {#S4-CBC}

#### Expected Structure

- [S4-CBC-01] CBC events defined by build_cbc_events().
  STATUS: DRAFTED
  CITE: R/utils/utils_distance_cbc.R:build_cbc_events():L20-L58

#### Observed Issues

Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED

#### Cleaning Rules Applied

Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED

#### Unresolved Issues

Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED

### Single-Health-System Care (SHS) {#S4-SHS}

#### Expected Structure

- [S4-SHS-01] Binary flag per patient.
  STATUS: DRAFTED
  CITE: R/169_single_source_care.R:compute_shs_flag():L1-L10

#### Observed Issues

Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED

#### Cleaning Rules Applied

Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED

#### Unresolved Issues

Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED

<!-- END REPO-ONLY DOMAINS -->

## 8. Open Questions and Decision Parking Lot

| Item | Notes | Date added | Map ID | Status | Cite |
|------|-------|------------|--------|--------|------|
| Manual: Claims as secondary source. Code: pipeline loads CDM only. Which should the manual record? | MISMATCH; D-191-01; S4-DXDT-01 | 2026-10-28 | S8-PRK-01 | DRAFTED | R/00_config.R:DUCKDB_PATH:L1-L5 |
| OneFLquestions document location unknown | OPEN-DEPENDENCY; DEC-001 | 2026-10-27 | S8-PRK-01 | DRAFTED | .planning/phases/190-evidence-map/190-01-SUMMARY.md |
  STATUS: DRAFTED
  CITE: .planning/phases/190-evidence-map/190-01-SUMMARY.md

## APPENDIX A. Embedded Working Tables

### A1. Data Ingest & Change Log

| Event | Type | Date | Source | Notes | Map ID | Status | Cite |
|-------|------|------|--------|-------|--------|--------|------|
| PCORnet CDM extract received | RECEIVED | 2025-09-15 | OneFlorida+ | Mailhot HL cohort | SA1-LOG-01 | DRAFTED | R/00_config.R:DUCKDB_PATH:L1-L5 |

### A3. Variable and Phenotype Decision Log

| Construct | Initial plan | Issue identified | Decision made | Rationale | Date | Affected analyses | Map ID | Status | Cite |
|-----------|-------------|-----------------|---------------|-----------|------|-------------------|--------|--------|------|
| CBC definition | Use LAB codes | None | Use build_cbc_events() | Repo implements this | 2026-10-01 | Phase 165 | SA3-DEC-01 | DRAFTED | R/utils/utils_distance_cbc.R:build_cbc_events():L20-L58 |

## Not drafted

- S3-DEC-01: Insufficient repo evidence.
