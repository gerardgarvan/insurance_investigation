# Requirements: PCORnet Payer Variable Investigation (R Pipeline)

**Defined:** 2026-03-24
**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Data Loading & Configuration

- [ ] **LOAD-01**: User can load 22 PCORnet CDM CSV tables with explicit column type specifications
- [ ] **LOAD-02**: User can parse dates in multiple SAS export formats (DATE9, DATETIME, YYYYMMDD)
- [ ] **LOAD-03**: User can configure file paths, ICD code lists (149 HL codes), and payer mappings via `00_config.R`

### Payer Harmonization

- [ ] **PAYR-01**: User can harmonize payer variables into 9 standard categories matching the Python pipeline (Medicare, Medicaid, Dual eligible, Private, Other government, No payment/Self-pay, Other, Unavailable, Unknown)
- [ ] **PAYR-02**: User can detect dual-eligible patients via temporal overlap of Medicare + Medicaid enrollment periods
- [ ] **PAYR-03**: User can generate per-partner enrollment completeness report (% with enrollment records, mean duration, gap patterns)

### Cohort Building

- [ ] **CHRT-01**: User can apply named filter predicates (`has_*`, `with_*`, `exclude_*`) that read like clinical protocol steps
- [ ] **CHRT-02**: User can see N patients before and after every filter step via automatic attrition logging
- [ ] **CHRT-03**: User can match HL diagnosis codes across both dotted (C81.10) and undotted (C8110) ICD formats

### Visualization

- [ ] **VIZ-01**: User can produce an attrition waterfall chart showing progressive cohort reduction through filter steps
- [ ] **VIZ-02**: User can produce a payer-stratified Sankey/alluvial diagram showing enrollment → diagnosis → treatment flow
- [ ] **VIZ-03**: User can apply HIPAA small-cell suppression (counts 1-10 suppressed) in all outputs

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Performance

- **PERF-01**: User can load CSVs via vroom for 10-100x faster I/O
- **PERF-02**: User can use arrow/parquet format for faster repeated reads

### Analysis

- **ANLY-01**: User can analyze payer × treatment initiation timing (days from diagnosis → first treatment by payer)
- **ANLY-02**: User can analyze payer × diagnosis timing (days from enrollment start → index diagnosis by payer)
- **ANLY-03**: User can produce payer distribution tables by site
- **ANLY-04**: User can produce missing data audit by site and year
- **ANLY-05**: User can run statistical models / regressions on payer disparities

### Reporting

- **REPT-01**: User can generate RMarkdown HTML report with inline figures
- **REPT-02**: User can produce publication-ready figure formatting

### Compliance

- **CMPL-01**: User can apply secondary suppression to prevent back-calculation of suppressed cells

### Automation

- **AUTO-01**: User can track filter chain provenance (which predicates applied in which order)
- **AUTO-02**: User can use tidylog for zero-manual-code attrition logging

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Shiny interactive app | v1 is working R scripts, not a deployed application |
| data.table rewrite | Conflicts with "reads like clinical protocol" design philosophy |
| Python pipeline replacement | R pipeline is parallel exploration tool, not a replacement |
| Mobile/web interface | Desktop RStudio only |
| Multi-cohort support | HL-specific for this project |
| Automated testing (testthat) | Exploration pipeline, not production software |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| LOAD-01 | Phase 1 | Pending |
| LOAD-02 | Phase 1 | Pending |
| LOAD-03 | Phase 1 | Pending |
| PAYR-01 | Phase 2 | Pending |
| PAYR-02 | Phase 2 | Pending |
| PAYR-03 | Phase 2 | Pending |
| CHRT-01 | Phase 3 | Pending |
| CHRT-02 | Phase 3 | Pending |
| CHRT-03 | Phase 3 | Pending |
| VIZ-01 | Phase 4 | Pending |
| VIZ-02 | Phase 5 | Pending |
| VIZ-03 | Phase 1 | Pending |

**Coverage:**
- v1 requirements: 12 total
- Mapped to phases: 12
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-24*
*Last updated: 2026-03-24 after initial definition*
