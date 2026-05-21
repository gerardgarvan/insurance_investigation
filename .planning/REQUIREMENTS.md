# Requirements: Unassigned Phases

**Defined:** 2026-05-19
**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## Gantt Chart Export (Phase 1)

- [x] **GANTT-01**: gantt_episodes.csv exists with correct column structure (patient_id, treatment_type, episode_number, episode_start, episode_stop, episode_length_days, distinct_dates_in_episode, historical_flag, triggering_codes) and contains all treatment episodes from the RDS artifacts
- [x] **GANTT-02**: gantt_detail.csv exists with correct column structure (patient_id, treatment_type, treatment_date, triggering_code, episode_number, episode_start, episode_stop, historical_flag) and contains all treatment episode detail rows from the RDS artifacts

## Gantt Code Descriptions (Phase 2)

- [ ] **GDESC-01**: gantt_detail.csv contains a triggering_code_description column with human-readable descriptions for each treatment code (e.g., J9000 shows "Doxorubicin HCl (Adriamycin)")
- [ ] **GDESC-02**: gantt_episodes.csv contains a triggering_code_descriptions column (plural) with comma-separated descriptions matching the order of the triggering_codes column
- [ ] **GDESC-03**: Code descriptions are built from a static lookup (no runtime API calls) combining Phase 39-41 RDS artifacts, R/45 hardcoded radiation descriptions, and R/00_config.R inline comments

## Cancer Site Confirmation by Distinct Date Count (Phase 3)

- [ ] **CCONF-01**: R/50_cancer_site_confirmation.R exists and produces cancer_site_confirmation.xlsx in output/tables/ with two sheets: "Exact Code" (confirmation at exact ICD-10 code level) and "Prefix Level" (confirmation at 3-character prefix level) -- per D-01, D-02
- [ ] **CCONF-02**: Confirmation logic uses DIAGNOSIS table only, DX_DATE for distinct-date counting, ICD-10 codes only (DX_TYPE == "10"), and counts a code as confirmed if a patient has 2+ distinct non-NA dates with that code -- per D-03, D-04
- [ ] **CCONF-03**: Each sheet contains columns: Cancer Site Category, Total Patients, Confirmed Patients, Unconfirmed Patients, Confirmation Rate; only populated categories shown (no zero-count rows) -- per D-05, D-06
- [ ] **CCONF-04**: Output is styled xlsx following openxlsx2 patterns (dark header fill, white font, freeze panes, number formatting, auto column widths) matching R/47 conventions -- per D-07

## Cancer Site Confirmation with 7-Day Separation (Phase 4)

- [ ] **C7DAY-01**: R/51_cancer_site_confirmation_7day.R exists as a separate script (clone of R/50, R/50 untouched) and produces cancer_site_confirmation_7day.xlsx in output/tables/ with two sheets: "Exact Code (7-Day Gap)" and "Prefix Level (7-Day Gap)" -- per D-01, D-02
- [ ] **C7DAY-02**: Confirmation logic uses DIAGNOSIS table only, DX_DATE for date span calculation, ICD-10 codes only (DX_TYPE == "10"), and counts a code as confirmed if max(DX_DATE) - min(DX_DATE) >= 7 days for a patient's dates with that code -- per D-04, D-06
- [ ] **C7DAY-03**: Each sheet contains columns: Cancer Site Category, Total Patients, Confirmed Patients, Unconfirmed Patients, Confirmation Rate; only populated categories shown (no zero-count rows); two confirmation levels: exact ICD-10 code and 3-character prefix -- per D-03, D-05
- [ ] **C7DAY-04**: Output is styled xlsx following openxlsx2 patterns from R/50 (dark header fill, white font, freeze panes, number formatting, auto column widths, totals row) -- per D-07

## All Codes Resolved XLSX Update (Phase 5)

- [x] **RESOLVE-01**: R/52_all_codes_resolved.R exists as a standalone script (R/42 untouched as historical record) and produces all_codes_resolved.xlsx with 6 sheets: Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care, and Summary -- per D-09, D-12, D-13
- [x] **RESOLVE-02**: Code lists are sourced exclusively from R/00_config.R TREATMENT_CODES vectors (not from combined_unmatched_report.xlsx or any other intermediate file) -- per D-01, D-02
- [x] **RESOLVE-03**: Each code has patient count and record count queried from PCORnet data via DuckDB (CPT/HCPCS from PROCEDURES, NDC from DISPENSING, RXNORM from PRESCRIBING+MED_ADMIN, ICD-10-PCS from PROCEDURES, DRG from ENCOUNTER) -- per D-03, D-04
- [x] **RESOLVE-04**: Code descriptions use multi-source cascade: (1) Phase 39-41 RDS artifacts, (2) R/45 hardcoded radiation descriptions, (3) R/00_config.R inline comments, (4) "No description available" fallback -- per D-06
- [x] **RESOLVE-05**: All 5 per-type resolved xlsx files are regenerated (chemotherapy_codes_resolved.xlsx, radiation_codes_resolved.xlsx, sct_codes_resolved.xlsx, immunotherapy_codes_resolved.xlsx, supportive_care_codes_resolved.xlsx) with Code, Meaning, Code Type, Source Table, Records, Patients columns and openxlsx2 styling -- per D-10, D-11
- [x] **RESOLVE-06**: R/00_config.R inline comments are updated where RDS/API sources provide a better description than the existing comment, using parse/source validation with rollback -- per D-07, D-08

## Cancer Summary Dataset (Phase 6)

- [ ] **CSUM-01**: R/53_cancer_summary.R exists and produces cancer_summary.xlsx and cancer_summary.csv in output/tables/ with one flat sheet ("Cancer Summary") containing patient-code level rows with columns: ID, cancer_code, description, two_or_more_unique_dates, two_or_more_unique_dates_gt_7, unique_dates_total, unique_dates_with_sep_gt_7 -- per D-01, D-02, D-12, D-13, D-15, D-16, D-17
- [ ] **CSUM-02**: Date confirmation metrics use DIAGNOSIS table only (DX_TYPE == "10"), ICD-10 neoplasm codes (C/D prefix), integer 1/0 flags for boolean columns, and correct NA handling (all-NA dates produce 0 for all metrics) -- per D-03, D-04, D-05, D-06, D-07, D-08, D-09
- [ ] **CSUM-03**: Description column combines PREFIX_MAP cancer site category name with code-level description from multi-source cascade (Phase 39-41 RDS, hardcoded, config comments), covering all patients in DIAGNOSIS (not restricted to HL cohort) -- per D-10, D-14
- [ ] **CSUM-04**: Output xlsx uses minimal styling (headers + data, auto column widths, integer number formatting on columns 4-7, no dark header fill) generated from scratch via openxlsx2 -- per D-11, D-18

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| GANTT-01 | Phase 1 | Complete |
| GANTT-02 | Phase 1 | Complete |
| GDESC-01 | Phase 2 | Pending |
| GDESC-02 | Phase 2 | Pending |
| GDESC-03 | Phase 2 | Pending |
| CCONF-01 | Phase 3 | Pending |
| CCONF-02 | Phase 3 | Pending |
| CCONF-03 | Phase 3 | Pending |
| CCONF-04 | Phase 3 | Pending |
| C7DAY-01 | Phase 4 | Pending |
| C7DAY-02 | Phase 4 | Pending |
| C7DAY-03 | Phase 4 | Pending |
| C7DAY-04 | Phase 4 | Pending |
| RESOLVE-01 | Phase 5 | Complete |
| RESOLVE-02 | Phase 5 | Complete |
| RESOLVE-03 | Phase 5 | Complete |
| RESOLVE-04 | Phase 5 | Complete |
| RESOLVE-05 | Phase 5 | Complete |
| RESOLVE-06 | Phase 5 | Complete |
| CSUM-01 | Phase 6 | Pending |
| CSUM-02 | Phase 6 | Pending |
| CSUM-03 | Phase 6 | Pending |
| CSUM-04 | Phase 6 | Pending |

**Coverage:**
- Unassigned phase requirements: 23 total
- Mapped to phases: 23
- Unmapped: 0

---
*Requirements defined: 2026-05-19*
*Last updated: 2026-05-21*
