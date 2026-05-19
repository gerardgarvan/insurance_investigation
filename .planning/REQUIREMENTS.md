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

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| GANTT-01 | Phase 1 | Complete |
| GANTT-02 | Phase 1 | Complete |
| GDESC-01 | Phase 2 | Pending |
| GDESC-02 | Phase 2 | Pending |
| GDESC-03 | Phase 2 | Pending |

**Coverage:**
- Unassigned phase requirements: 5 total
- Mapped to phases: 5
- Unmapped: 0

---
*Requirements defined: 2026-05-19*
*Last updated: 2026-05-19*
