# Requirements: PCORnet Payer Variable Investigation (R Pipeline)

**Defined:** 2026-06-12
**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## v3.2 Requirements

Requirements for meeting gap resolution report milestone. Each maps to roadmap phases.

### Treatment Timing Investigations

- [x] **TIMING-01**: User can run R script that flags and quantifies all treatment episodes (chemo, radiation, SCT, immunotherapy) occurring before the patient's first confirmed HL diagnosis date, with counts by treatment type
- [x] **TIMING-02**: User can run R script that produces a secondary malignancy table using 7-day gap criterion between diagnoses, with columns K-N based on population in column E (E3 per meeting notes)

### Code Verification Investigations

- [ ] **CODE-01**: User can run R script that investigates "Ethna" immunotherapy classification, verifying whether it appears in current code mappings and recommending correction
- [ ] **CODE-02**: User can run R script that cross-checks organ transplant code (line 11 of all_codes_resolved spreadsheet) against current SCT code mappings and patient data
- [ ] **CODE-03**: User can run R script that verifies SCT codes above line 22 in the codes spreadsheet against actual patient data, flagging codes with zero or suspicious usage

### HL+NHL Overlap Validation

- [ ] **OVERLAP-01**: User can run R script that produces a focused validation report on HL+NHL dual-code patients (~4,000 of 8,000), extending R/77-R/78 with patient-level detail and data quality assessment

### Tableau-Ready Tables

- [x] **TABLE-01**: User can open xlsx with TABLE 1: each encounter ID mapped to all associated cancer diagnosis codes (comma-separated), suitable for Tableau import
- [x] **TABLE-02**: User can open xlsx with TABLE 2: chemotherapy drugs by class/category with associated cancer codes per encounter, suitable for Tableau import

### Reporting & Delivery

- [x] **REPORT-01**: User can render an RMarkdown report to self-contained HTML that compiles all investigation findings (G4, G5, G8, G10, G11, secondary malignancy) with tables and summaries
- [x] **REPORT-02**: User can run a data delivery manifest script that identifies all output files created/updated in v3.1 and v3.2, lists them with descriptions, and generates a file listing for packaging to Amy
- [x] **REPORT-03**: User can review updated pecan_lymphoma_meeting_notes_combined.md with resolved gaps marked and stale items removed

### V2 Cancer Summary Table Fix (Phase 110)

- [x] **V2FIX-01**: V2 cancer summary table population restricted to patients with HL-specific 7-day gap confirmation (C81 + 201.x codes with 2+ unique dates spanning 7+ days), replacing the previous any-cancer-code 7-day filter
- [x] **V2FIX-02**: K-L-M columns (Pre-HL, Post-HL, Both) only count secondary malignancies that themselves meet the 7-day gap confirmation criterion for each respective code
- [x] **V2FIX-03**: R/88 smoke test validates the updated V2 population assertion bounds and HL-specific filtering pattern

### TABLE-2 Date-Grain Collapse (Phase 111)

- [x] **T2COLLAPSE-01**: TABLE-2 xlsx output collapsed from per-encounter+medication grain to per-patient+date grain with 5 columns (PATID, treatment_date, agents, cancer_codes, cancer_category_names), agents alphabetically sorted and deduplicated, cancer codes merged across encounters sharing same patient+date
- [x] **T2COLLAPSE-02**: R/88 smoke test validates the new TABLE-2 date-grain column structure including agents collapse pattern, cancer_codes split-union merge, and group_by patient+date grouping

### Gantt Temporal Diagnosis + Sort Audit (Phase 112)

- [x] **GANTT-DX-01**: Gantt episode data enriched with two new columns (episode_dx_codes, episode_dx_categories) capturing all cancer diagnoses within +/-30 days of each episode's span, aggregated per episode with deduplication and ascending alphabetical sort
- [x] **GANTT-DX-02**: gantt_episodes.csv schema expanded from 22 to 24 columns with the two new temporal diagnosis columns, Gantt detail schema unchanged at 20 columns
- [x] **SORT-01**: All multi-value fields across the Gantt export pipeline (R/52 clean_multi_value, R/26 aggregations, R/36 TABLE-2, R/57 drug grouping) enforce ascending alphabetical sort with no exceptions
- [x] **SORT-02**: R/36 TABLE-2 cancer_category_names and R/57 drug grouping cancer_category_names changed from descending to ascending sort
- [x] **SMOKE-112-01**: R/88 smoke test validates Phase 112 temporal diagnosis columns, schema extension, sort direction fixes, and clean_multi_value sort enforcement

### Post-Death Encounter Investigation (Phase 113)

- [x] **POSTDEATH-01**: User can run R/51 and see a two-sheet xlsx (Patient Summary + Event Detail) quantifying temporal gaps in days for all post-death encounters, diagnoses, and treatments across ~200 patients, with bucketed distribution (0-30 days, 31-90 days, 91-365 days, >1 year) and per-event source_table labels (ENCOUNTER, DIAGNOSIS, TREATMENT)
- [x] **POSTDEATH-02**: R/88 smoke test validates R/51 structural integrity including death_valid filtering, DuckDB queries, bucket assignment, source_table labels, and styled xlsx output
- [x] **POSTDEATH-03**: R/39 pipeline runner includes R/51 in the investigation scripts stage

### Drug Name Consistency Remediation (Phase 114)

- [ ] **DRUGFIX-01**: R/26 fills blank drug_names at detail grain from MEDICATION_LOOKUP (reference Excel Medication column) via coalesce after RxNorm join, before episode aggregation, with fill statistics logged
- [ ] **DRUGFIX-02**: R/42 code_descriptions.rds uses reference Excel medication names (MEDICATION_LOOKUP) as 5th and highest-priority source in the precedence chain, overriding API-sourced and hardcoded descriptions for codes present in the reference Excel
- [ ] **DRUGFIX-03**: MEDICATION_LOOKUP named character vector centralized in R/00_config.R, built from all 5 sheets (Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care) of all_codes_resolved_next_tables_v2.1.xlsx with 400+ entries and title-case normalization
- [ ] **DRUGFIX-04**: User can run R/79 standalone audit script and see a two-sheet styled xlsx (Summary with blank/inconsistency counts, Detail with per-code before/after values) documenting all remediation impact
- [ ] **DRUGFIX-05**: R/88 smoke test validates Phase 114 structural integrity (MEDICATION_LOOKUP existence, R/26 fill logic, R/42 5-source precedence, R/79 audit script structure) and R/39 pipeline runner includes R/79

## v3.1 Requirements (Complete)

### Broadened Drug Grouping

- [x] **DRUG-01**: drug_grouping_instances output includes ALL treatment encounters regardless of cancer diagnosis linkage (broadened from cancer-linked-only)
- [x] **DRUG-02**: Flag column indicating whether each encounter has a linked cancer diagnosis (cancer_linked = TRUE/FALSE)
- [x] **DRUG-03**: Existing cancer-linked-only output preserved alongside broadened version (no breaking change)

### Co-Administration Analysis

- [x] **COADMIN-01**: Detail table showing each single-agent chemo encounter with all co-administered chemotherapies found within ±30 days
- [x] **COADMIN-02**: Pattern summary table showing most common co-administration pairings and their frequencies

### Death Date Summary

- [x] **DEATH-01**: Unstratified cross-tab table answering: (i) how many patients have a death date, (ii) of those how many have death as their last encounter, (iii) how many have encounters after their death date

### CONDITION Table Linkage

- [x] **COND-01**: CONDITION table added as 3rd tier in cancer linkage cascade (DIAGNOSIS direct -> temporal fallback -> CONDITION supplement)
- [x] **COND-02**: Linkage improvement report showing before/after unlinked episode rates
- [x] **COND-03**: Previously unlinked episodes re-classified to linked cancer categories via CONDITION data

## Future Requirements

### Extended Analysis (v3.3+)

- **DRUG-04**: Stratified drug grouping instances by payer category
- **COADMIN-03**: Co-administration patterns stratified by cancer type
- **DEATH-02**: Death date cross-tabs stratified by treatment type and payer category

## Out of Scope

| Feature | Reason |
|---------|--------|
| Insurance category consolidation (8->fewer) | Superseded by AMC 8-category framework; team settled on current mapping |
| Tableau visualization building | Visualization is downstream; Amy builds Tableau from R outputs. R pipeline provides Tableau-ready data tables. |
| Sharon's medication review integration | Waiting on external clinical review; will incorporate when received |
| Regimen reconstruction beyond ABVD/BV+AVD/Nivo+AVD | Current 3-regimen detection covers ~95% of adult first-line HL |
| CONDITION table for non-cancer linkage | Scope limited to cancer diagnosis improvement |
| PDF RMarkdown output | HTML is primary format for easy sharing; PDF can be added later if needed |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| COND-01 | Phase 100 | Complete |
| COND-02 | Phase 100 | Complete |
| COND-03 | Phase 100 | Complete |
| DRUG-01 | Phase 101 | Complete |
| DRUG-02 | Phase 101 | Complete |
| DRUG-03 | Phase 101 | Complete |
| COADMIN-01 | Phase 102 | Complete |
| COADMIN-02 | Phase 102 | Complete |
| DEATH-01 | Phase 103 | Complete |
| TIMING-01 | Phase 104 | Complete |
| TIMING-02 | Phase 104 | Complete |
| CODE-01 | Phase 105 | Pending |
| CODE-02 | Phase 105 | Pending |
| CODE-03 | Phase 105 | Pending |
| OVERLAP-01 | Phase 105 | Pending |
| TABLE-01 | Phase 106 | Complete |
| TABLE-02 | Phase 106 | Complete |
| REPORT-01 | Phase 107 | Complete |
| REPORT-02 | Phase 107 | Complete |
| REPORT-03 | Phase 107 | Complete |
| V2FIX-01 | Phase 110 | Complete |
| V2FIX-02 | Phase 110 | Complete |
| V2FIX-03 | Phase 110 | Complete |
| T2COLLAPSE-01 | Phase 111 | Complete |
| T2COLLAPSE-02 | Phase 111 | Complete |
| GANTT-DX-01 | Phase 112 | Complete |
| GANTT-DX-02 | Phase 112 | Complete |
| SORT-01 | Phase 112 | Complete |
| SORT-02 | Phase 112 | Complete |
| SMOKE-112-01 | Phase 112 | Complete |
| POSTDEATH-01 | Phase 113 | Complete |
| POSTDEATH-02 | Phase 113 | Complete |
| POSTDEATH-03 | Phase 113 | Complete |
| DRUGFIX-01 | Phase 114 | Pending |
| DRUGFIX-02 | Phase 114 | Pending |
| DRUGFIX-03 | Phase 114 | Pending |
| DRUGFIX-04 | Phase 114 | Pending |
| DRUGFIX-05 | Phase 114 | Pending |

**Coverage:**
- v3.2 requirements: 11 total
- Mapped to phases: 11
- Unmapped: 0
- Phase 108-110 requirements: 12 total (WARN x6, COADMIN-FIX x3, V2FIX x3)
- Phase 111 requirements: 2 total (T2COLLAPSE x2)
- Phase 112 requirements: 5 total (GANTT-DX x2, SORT x2, SMOKE-112 x1)
- Phase 113 requirements: 3 total (POSTDEATH x3)
- Phase 114 requirements: 5 total (DRUGFIX x5)

---
*Requirements defined: 2026-06-12*
*Last updated: 2026-06-24 -- Phase 114 DRUGFIX requirements added*
