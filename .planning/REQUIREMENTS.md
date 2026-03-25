# Requirements: PCORnet Payer Variable Investigation (R Pipeline)

**Defined:** 2026-03-24
**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Data Loading & Configuration

- [x] **LOAD-01**: User can load 22 PCORnet CDM CSV tables with explicit column type specifications
- [x] **LOAD-02**: User can parse dates in multiple SAS export formats (DATE9, DATETIME, YYYYMMDD)
- [x] **LOAD-03**: User can configure file paths, ICD code lists (149 HL codes), and payer mappings via `00_config.R`

### Payer Harmonization

- [x] **PAYR-01**: User can harmonize payer variables into 9 standard categories matching the Python pipeline (Medicare, Medicaid, Dual eligible, Private, Other government, No payment/Self-pay, Other, Unavailable, Unknown)
- [x] **PAYR-02**: User can detect dual-eligible patients via temporal overlap of Medicare + Medicaid enrollment periods
- [x] **PAYR-03**: User can generate per-partner enrollment completeness report (% with enrollment records, mean duration, gap patterns)

### Cohort Building

- [x] **CHRT-01**: User can apply named filter predicates (`has_*`, `with_*`, `exclude_*`) that read like clinical protocol steps
- [x] **CHRT-02**: User can see N patients before and after every filter step via automatic attrition logging
- [x] **CHRT-03**: User can match HL diagnosis codes across both dotted (C81.10) and undotted (C8110) ICD formats

### Visualization

- [ ] **VIZ-01**: User can produce an attrition waterfall chart showing progressive cohort reduction through filter steps
- [ ] **VIZ-02**: User can produce a payer-stratified Sankey/alluvial diagram showing enrollment → diagnosis → treatment flow
- [ ] **VIZ-03**: User can apply HIPAA small-cell suppression (counts 1-10 suppressed) in all outputs

### Data Quality & Parsing Fixes

- [x] **FIX-01**: User can identify and fix date parsing failures across all 9 PCORnet CDM tables with diagnostic CSV output
- [x] **FIX-02**: User can identify HL patients via BOTH DIAGNOSIS table (ICD-9/10) AND TUMOR_REGISTRY histology codes (ICD-O-3 9650-9667)
- [x] **FIX-03**: User can run a reusable diagnostic script (07_diagnostics.R) that audits column types, date regex coverage, encoding issues, and numeric ranges
- [x] **FIX-04**: User can audit payer mapping correctness with comparison against Python pipeline reference counts

### Data Quality Remediation (Phase 6)

- [x] **RECT-01**: User can track HL identification source (DIAGNOSIS only, TR only, Both) per patient with HL_SOURCE column in cohort output
- [x] **RECT-02**: User can exclude patients without HL evidence ("Neither" source) from final cohort, with excluded patients written to separate audit CSV
- [x] **RECT-03**: User can fix date parsing, column types, date regex, and numeric validation issues identified by 07_diagnostics.R based on actual diagnostic output
- [x] **RECT-04**: User can view R vs Python payer mapping differences documented side-by-side in code comments
- [x] **RECT-05**: User can rebuild full pipeline end-to-end after fixes and verify all issues are resolved or explained via data_quality_summary.csv

### Gap Analysis (Phase 7)

- [ ] **GAP-01**: User can view complete diagnosis history for all excluded "Neither" patients including lymphoma/cancer code subset (C81-C96, 200-208) stratified by site
- [ ] **GAP-02**: User can see per-patient gap classification (phantom record, coding gap, non-HL diagnoses only, etc.) with enrollment and tumor registry cross-reference
- [ ] **GAP-03**: User can determine whether the HL identification gap is closable (missed ICD codes) or a data quality limitation (no HL-related codes present)

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Performance

- **PERF-01**: User can load CSVs via vroom for 10-100x faster I/O
- **PERF-02**: User can use arrow/parquet format for faster repeated reads

### Analysis

- **ANLY-01**: User can analyze payer x treatment initiation timing (days from diagnosis -> first treatment by payer)
- **ANLY-02**: User can analyze payer x diagnosis timing (days from enrollment start -> index diagnosis by payer)
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
| LOAD-01 | Phase 1 | Complete |
| LOAD-02 | Phase 1 | Complete |
| LOAD-03 | Phase 1 | Complete |
| PAYR-01 | Phase 2 | Complete |
| PAYR-02 | Phase 2 | Complete |
| PAYR-03 | Phase 2 | Complete |
| CHRT-01 | Phase 3 | Complete |
| CHRT-02 | Phase 3 | Complete |
| CHRT-03 | Phase 3 | Complete |
| VIZ-01 | Phase 4 | Pending |
| VIZ-02 | Phase 4 | Pending |
| VIZ-03 | Phase 4 | Pending |
| FIX-01 | Phase 5 | Complete |
| FIX-02 | Phase 5 | Complete |
| FIX-03 | Phase 5 | Complete |
| FIX-04 | Phase 5 | Complete |
| RECT-01 | Phase 6 | Complete |
| RECT-02 | Phase 6 | Complete |
| RECT-03 | Phase 6 | Complete |
| RECT-04 | Phase 6 | Complete |
| RECT-05 | Phase 6 | Complete |
| GAP-01 | Phase 7 | Pending |
| GAP-02 | Phase 7 | Pending |
| GAP-03 | Phase 7 | Pending |

**Coverage:**
- v1 requirements: 24 total
- Mapped to phases: 24
- Unmapped: 0

---
*Requirements defined: 2026-03-24*
*Last updated: 2026-03-25 after Phase 7 planning*
