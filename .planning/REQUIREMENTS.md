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

**Coverage:**
- Unassigned phase requirements: 9 total
- Mapped to phases: 9
- Unmapped: 0

---
*Requirements defined: 2026-05-19*
*Last updated: 2026-05-19*
