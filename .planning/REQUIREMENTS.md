# Requirements: PCORnet Payer Variable Investigation (R Pipeline)

**Defined:** 2026-06-12
**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## v3.2 Requirements

Requirements for meeting gap resolution report milestone. Each maps to roadmap phases.

### Treatment Timing Investigations

- [ ] **TIMING-01**: User can run R script that flags and quantifies all treatment episodes (chemo, radiation, SCT, immunotherapy) occurring before the patient's first confirmed HL diagnosis date, with counts by treatment type
- [ ] **TIMING-02**: User can run R script that produces a secondary malignancy table using 7-day gap criterion between diagnoses, with columns K-N based on population in column E (E3 per meeting notes)

### Code Verification Investigations

- [ ] **CODE-01**: User can run R script that investigates "Ethna" immunotherapy classification, verifying whether it appears in current code mappings and recommending correction
- [ ] **CODE-02**: User can run R script that cross-checks organ transplant code (line 11 of all_codes_resolved spreadsheet) against current SCT code mappings and patient data
- [ ] **CODE-03**: User can run R script that verifies SCT codes above line 22 in the codes spreadsheet against actual patient data, flagging codes with zero or suspicious usage

### HL+NHL Overlap Validation

- [ ] **OVERLAP-01**: User can run R script that produces a focused validation report on HL+NHL dual-code patients (~4,000 of 8,000), extending R/77-R/78 with patient-level detail and data quality assessment

### Tableau-Ready Tables

- [ ] **TABLE-01**: User can open xlsx with TABLE 1: each encounter ID mapped to all associated cancer diagnosis codes (comma-separated), suitable for Tableau import
- [ ] **TABLE-02**: User can open xlsx with TABLE 2: chemotherapy drugs by class/category with associated cancer codes per encounter, suitable for Tableau import

### Reporting & Delivery

- [ ] **REPORT-01**: User can render an RMarkdown report to self-contained HTML that compiles all investigation findings (G4, G5, G8, G10, G11, secondary malignancy) with tables and summaries
- [ ] **REPORT-02**: User can run a data delivery manifest script that identifies all output files created/updated in v3.1 and v3.2, lists them with descriptions, and generates a file listing for packaging to Amy
- [ ] **REPORT-03**: User can review updated pecan_lymphoma_meeting_notes_combined.md with resolved gaps marked and stale items removed

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

- [x] **COND-01**: CONDITION table added as 3rd tier in cancer linkage cascade (DIAGNOSIS direct → temporal fallback → CONDITION supplement)
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
| Insurance category consolidation (8→fewer) | Superseded by AMC 8-category framework; team settled on current mapping |
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
| TIMING-01 | — | Pending |
| TIMING-02 | — | Pending |
| CODE-01 | — | Pending |
| CODE-02 | — | Pending |
| CODE-03 | — | Pending |
| OVERLAP-01 | — | Pending |
| TABLE-01 | — | Pending |
| TABLE-02 | — | Pending |
| REPORT-01 | — | Pending |
| REPORT-02 | — | Pending |
| REPORT-03 | — | Pending |

**Coverage:**
- v3.2 requirements: 11 total
- Mapped to phases: 0 (awaiting roadmap creation)
- Unmapped: 11

---
*Requirements defined: 2026-06-12*
*Last updated: 2026-06-12 — v3.2 requirements added*
