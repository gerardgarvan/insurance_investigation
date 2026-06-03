# Requirements: PCORnet Payer Variable Investigation — v2.1 Clinical Data Refinements & NLPHL Breakout

**Defined:** 2026-06-02
**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## v2.1 Requirements

Requirements for clinical data refinements, NLPHL breakout, treatment pipeline changes, death data integration, code verification, and visualization.

### Cancer Classification

- [x] **CANCER-01**: NLPHL (C81.0 / 201.4x) broken out from Hodgkin Lymphoma as distinct cancer category in CANCER_SITE_MAP, classify_codes(), and all downstream outputs including Gantt
- [ ] **CANCER-02**: Pre/post cancer summary table requires 7-day unique day gap for ALL cancer categories (not just HL), with total population = 6,347
- [ ] **CANCER-03**: Cancer_category and triggering code description populated per episode using drug groupings from all_codes_resolved_next_tables.xlsx

### Treatment Pipeline

- [x] **TREAT-01**: All treatment data sourced from tumor registry dropped from treatment episode pipeline
- [ ] **TREAT-02**: Drug groupings loaded from all_codes_resolved_next_tables.xlsx and centralized in R/00_config.R
- [ ] **TREAT-03**: Two new summary tables matching all_codes_resolved_next_tables.xlsx Sheet1 templates: (1) treatment-type-level summary (Chemo, Radiation, SCT, Immunotherapy) with cancer codes and encounter counts, (2) drug-level summary (individual drugs/treatments) with cancer codes and encounter counts

### Death Data

- [x] **DEATH-01**: Cause of death data quality profiled (completeness, coding, payer stratification) before integration
- [x] **DEATH-02**: Cause of death included in outputs (conditional on DEATH-01 showing acceptable data quality)

### Code Verification

- [ ] **CODE-01**: "Replaced by" codes from all_codes_resolved_next_tables.xlsx verified against existing code mappings
- [ ] **CODE-02**: 90 patients with SCT code 0362 investigated for other related SCT codes during same encounters

### Quality Standards

- [x] **QUAL-01**: All new/modified scripts follow v2.0 standards (styler formatting, lintr compliance, checkmate assertions, documentation headers, smoke test updates)

## Future Requirements

### Visualization (deferred from v2.1)

- **VIZ-01**: Attrition waterfall chart produced from filter log
- **VIZ-02**: Sankey/alluvial diagram stratified by payer
- **VIZ-03**: HIPAA small-cell suppression applied in all outputs

### v3.0+ Considerations

- **ORCH-01**: Pipeline orchestration via targets/drake (if pipeline grows >100 scripts)
- **CI-01**: CI/CD integration with automated lintr on PRs (if team grows >3 developers)
- **LOG-01**: Structured logging via logger package (if machine-readable logs needed)
- **PKG-01**: Full R package conversion with NAMESPACE/DESCRIPTION (if distributing pipeline)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Stanford V / BEACOPP regimen identification | Only 3 regimens (ABVD, BV+AVD, Nivo+AVD) cover ~95% of adult first-line |
| Pediatric protocols (age <21) | Adult protocols only for v1.x-v2.x |
| Multi-line therapy sequencing | Requires episode boundary formalization first |
| Statistical modeling / regression | Exploration only; not in scope |
| Publication-ready figure formatting | Exploratory quality sufficient |
| RMarkdown / Shiny rendering | Raw R scripts and PNG figures |
| Full R package conversion | Over-engineering for analysis pipeline |
| Pipeline orchestration (targets/drake) | Major architecture change; defer to v3+ |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CANCER-01 | Phase 75, 77 | Complete |
| CANCER-02 | Phase 77 | Pending |
| CANCER-03 | Phase 78 | Pending |
| TREAT-01 | Phase 76 | Complete |
| TREAT-02 | Phase 77 | Pending |
| TREAT-03 | Phase 79 | Pending |
| DEATH-01 | Phase 75, 78 | Complete |
| DEATH-02 | Phase 75, 78 | Complete |
| CODE-01 | Phase 79 | Pending |
| CODE-02 | Phase 79 | Pending |
| QUAL-01 | Phases 75-80 (all) | Complete |

**Coverage:**
- v2.1 requirements: 11 total
- Mapped to phases: 11 (100%)
- Unmapped: 0

---
*Requirements defined: 2026-06-02*
*Last updated: 2026-06-02 after plan revision (coverage analysis added to Phase 76)*
