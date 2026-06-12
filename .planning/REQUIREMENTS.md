# Requirements: PCORnet Payer Variable Investigation (R Pipeline)

**Defined:** 2026-06-12
**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## v3.1 Requirements

Requirements for meeting gap closure milestone. Each maps to roadmap phases.

### Broadened Drug Grouping

- [ ] **DRUG-01**: drug_grouping_instances output includes ALL treatment encounters regardless of cancer diagnosis linkage (broadened from cancer-linked-only)
- [ ] **DRUG-02**: Flag column indicating whether each encounter has a linked cancer diagnosis (cancer_linked = TRUE/FALSE)
- [ ] **DRUG-03**: Existing cancer-linked-only output preserved alongside broadened version (no breaking change)

### Co-Administration Analysis

- [ ] **COADMIN-01**: Detail table showing each single-agent chemo encounter with all co-administered chemotherapies found within ±30 days
- [ ] **COADMIN-02**: Pattern summary table showing most common co-administration pairings and their frequencies

### Death Date Summary

- [ ] **DEATH-01**: Unstratified cross-tab table answering: (i) how many patients have a death date, (ii) of those how many have death as their last encounter, (iii) how many have encounters after their death date

### CONDITION Table Linkage

- [x] **COND-01**: CONDITION table added as 3rd tier in cancer linkage cascade (DIAGNOSIS direct → temporal fallback → CONDITION supplement)
- [x] **COND-02**: Linkage improvement report showing before/after unlinked episode rates
- [x] **COND-03**: Previously unlinked episodes re-classified to linked cancer categories via CONDITION data

## Future Requirements

### Extended Analysis (v3.2+)

- **DRUG-04**: Stratified drug grouping instances by payer category
- **COADMIN-03**: Co-administration patterns stratified by cancer type
- **DEATH-02**: Death date cross-tabs stratified by treatment type and payer category

## Out of Scope

| Feature | Reason |
|---------|--------|
| Payer category consolidation (8→5) | Team decided to defer; current 8-category system retained for analytical granularity |
| Tableau visualization | Visualization is downstream of R pipeline; Amy builds Tableau from R outputs |
| Sharon's medication review integration | Waiting on external clinical review; will incorporate when received |
| Regimen reconstruction beyond ABVD/BV+AVD/Nivo+AVD | Current 3-regimen detection covers ~95% of adult first-line HL; additional regimens need clinical validation |
| CONDITION table for non-cancer linkage | Scope limited to cancer diagnosis improvement; general CONDITION usage is separate concern |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| COND-01 | Phase 100 | Complete |
| COND-02 | Phase 100 | Complete |
| COND-03 | Phase 100 | Complete |
| DRUG-01 | Phase 101 | Pending |
| DRUG-02 | Phase 101 | Pending |
| DRUG-03 | Phase 101 | Pending |
| COADMIN-01 | Phase 102 | Pending |
| COADMIN-02 | Phase 102 | Pending |
| DEATH-01 | Phase 103 | Pending |

**Coverage:**
- v3.1 requirements: 9 total
- Mapped to phases: 9 (100% coverage)
- Unmapped: 0

---
*Requirements defined: 2026-06-12*
*Last updated: 2026-06-12 after v3.1 roadmap creation*
