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
- [ ] **VIZ-02**: User can produce a payer-stratified Sankey/alluvial diagram showing enrollment -> diagnosis -> treatment flow
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

### Treatment-Anchored Payer Mode (Phase 8)

- [x] **TPAY-01**: User can see first treatment dates (FIRST_CHEMO_DATE, FIRST_RADIATION_DATE, FIRST_SCT_DATE) in hl_cohort output, derived from PROCEDURES (all PX_TYPE values) and PRESCRIBING (chemo only)
- [x] **TPAY-02**: User can see payer mode at each treatment type (PAYER_AT_CHEMO, PAYER_AT_RADIATION, PAYER_AT_SCT) computed within +-30 days of first treatment date, using the same mode calculation as PAYER_CATEGORY_AT_FIRST_DX
- [x] **TPAY-03**: User can see logged match counts per treatment type (N matched, M no encounters in window set to NA) for transparency about payer assignment coverage

### Expanded Treatment Detection (Phase 9)

- [x] **TXEXP-01**: User can detect treatment via DISPENSING and MED_ADMIN tables (RXNORM_CUI matching for chemo drugs)
- [x] **TXEXP-02**: User can detect treatment via DIAGNOSIS-based evidence codes (Z51.11/Z51.12/Z51.0 for chemo/radiation; Z94.84/T86.5/T86.09 for SCT)
- [x] **TXEXP-03**: User can detect treatment via ENCOUNTER DRG codes (837-839, 846-848 for chemo; 849 for radiation; 014-017 for SCT)
- [x] **TXEXP-04**: User can detect treatment via PROCEDURES revenue codes (PX_TYPE="RE": 0331/0332/0335 for chemo; 0330/0333 for radiation; 0362/0815 for SCT)
- [x] **TXEXP-05**: User can see aggregate source contribution counts per treatment type logged to console (e.g., "Sources: TR=X, PX=Y, DX=Z, DRG=W")
- [x] **TXEXP-06**: User can see expanded treatment-anchored payer dates from all new sources feeding into PAYER_AT_CHEMO/RADIATION/SCT computation

### Surveillance & Survivorship (Phase 10)

- [x] **SURV-01**: User can configure surveillance modality CPT/HCPCS/LOINC code lists and lab LOINC codes in 00_config.R, transcribed from VariableDetails.xlsx
- [x] **SURV-02**: User can detect post-diagnosis surveillance modalities (Mammogram, Breast MRI, Echocardiogram, Stress test, ECG, MUGA, PFT, TSH, CBC) via PROCEDURES and LAB_RESULT_CM tables
- [x] **SURV-03**: User can detect post-diagnosis lab results (CRP, ALT, AST, ALP, GGT, bilirubin, platelets, FOBT) via LAB_RESULT_CM LOINC matching
- [x] **SURV-04**: User can see surveillance and lab columns (HAD_/FIRST_/N_ per modality) in hl_cohort.csv output

- [x] **SVENC-01**: User can configure survivorship ICD codes and cancer provider NUCC taxonomy codes in 00_config.R, and load PROVIDER + LAB_RESULT_CM tables
- [x] **SVENC-02**: User can classify post-diagnosis encounters into 4 survivorship levels (non-acute, cancer-related, cancer-provider, survivorship) per VariableDetails.xlsx definitions
- [x] **SVENC-03**: User can see per-patient survivorship encounter flags (HAD_/N_/FIRST_ per level) using ENCOUNTER, DIAGNOSIS, and PROVIDER table joins
- [x] **SVENC-04**: User can see survivorship encounter columns in hl_cohort.csv output

- [x] **TDOC-01**: User can see timing derivation columns (DAYS_DX_TO_CHEMO, DAYS_DX_TO_RADIATION, DAYS_DX_TO_SCT) in hl_cohort.csv output
- [x] **TDOC-02**: User can run an R script that auto-generates comprehensive variable documentation covering all pipeline variables (treatment, surveillance, labs, survivorship, payer, cohort, timing)
- [x] **TDOC-03**: User can get documentation output as both .md (source of truth) and .docx (sharing copy), generated programmatically from 00_config.R code lists

### PPTX Clarity & Missing Data Consolidation (Phase 11)

- [x] **PPTX-01**: User can see a single "Missing" category in all PPTX tables replacing Unknown, Unavailable, Other, and No Information payer labels
- [x] **PPTX-02**: User can see column totals on every PPTX table (bold row with header-matching styling)
- [x] **PPTX-03**: User can see encounter analysis slides in PPTX: histogram of encounters per person by payor, post-treatment encounters by DX year, total encounters by DX year
- [x] **PPTX-04**: User can see age group breakdown (0-17, 18-39, 40-64, 65+) with Yes/No post-treatment encounter analysis in PPTX
- [x] **PPTX-05**: User can see unambiguous slide titles, subtitles, and labels throughout PPTX with no vague terminology

### More PPTX Polishing (Phase 12)

- [x] **PPTX2-01**: User can see a definitions/glossary slide as the first slide with all payer term definitions (Primary Insurance, First Diagnosis, First/Last treatment types, Post-Treatment Insurance, Missing, No Payer Assigned, N/A labels, ENR coverage terms)
- [x] **PPTX2-02**: User can see contextual footnotes on every data slide (small italic text at slide bottom) defining the terms used on that specific slide
- [x] **PPTX2-03**: User can see Slide 16 without the "No Treatment Recorded" row (row removed)
- [ ] **PPTX2-04**: User can see the encounter histogram with payer categories consolidated to 6+Missing (matching table consolidation) and a >500 overflow bin with per-facet count annotation
- [x] **PPTX2-05**: User can see a summary statistics slide after the encounter histogram showing N, Mean, Median, Min, Q1, Q3, Max, N>500 per payer category
- [x] **PPTX2-06**: User can see DX year bar charts (Slides 19-20) without DX_YEAR=1900 data points, with a footnote noting how many patients with masked diagnosis date were excluded
- [ ] **PPTX2-07**: User can see age group bar chart labels that are not clipped at the top of the plot

### CSV Values Data Audit & Code Optimization (Phase 14)

- [x] **CSVAUDIT-01**: User can review value_audit CSV output (from 17_value_audit.R) for coding inconsistencies with Claude in conversation
- [x] **CSVAUDIT-02**: User can identify and discuss which coding inconsistencies represent real data capture problems vs expected PCORnet CDM variation
- [x] **OPTIM-01**: User can see dead code removed and redundant operations consolidated across R scripts 00-17 (TUMOR_REGISTRY bind_rows, duplicate HIPAA suppression, unused variables)
- [x] **OPTIM-02**: User can see style-preserving optimizations (reduced bind_rows duplication, consolidated PROCEDURES queries, early column selection) applied to the pipeline without changing function signatures

## v1.1 Requirements

Requirements for milestone v1.1: RDS Cache & Visualization Polish.

### RDS Caching

- [x] **CACHE-01**: After each raw PCORnet table is loaded and validated, serialize it to `.rds` in `/blue/erin.mobley-hl.bcu/clean/rds/raw/` with consistent naming (e.g., `ENROLLMENT.rds`, `DIAGNOSIS.rds`)
- [x] **CACHE-02**: At pipeline startup, check if `.rds` exists and is newer than source CSV — load from `.rds` via `readRDS()` if so, log `[CACHE HIT]` vs `[CSV PARSE]` per table
- [x] **CACHE-03**: `FORCE_RELOAD` flag in `00_config.R` (default `FALSE`) bypasses cache and re-parses all CSVs when set to `TRUE`
- [x] **CACHE-04**: Log wall-clock time saved per table when loading from cache vs CSV

### Dataset Snapshots

- [x] **SNAP-01**: After each named filter step in cohort chain, save resulting data frame to `/blue/erin.mobley-hl.bcu/clean/rds/cohort/` as `cohort_<step_name>.rds`
- [x] **SNAP-02**: Save final analysis-ready cohort as `cohort_final.rds` and attrition log as `attrition_log.rds`
- [x] **SNAP-03**: Every figure gets its ggplot-ready data frame saved as `<figure_name>_data.rds` in `/blue/erin.mobley-hl.bcu/clean/rds/outputs/`
- [x] **SNAP-04**: Every summary table gets its source data frame saved as `<table_name>_data.rds` before rendering
- [x] **SNAP-05**: Shared `save_output_data(df, name)` helper function for consistent path construction, logging, and `saveRDS()`

### Git Exclusion

- [x] **GIT-01**: Add `/blue/erin.mobley-hl.bcu/clean/` to `.gitignore`
- [x] **GIT-02**: Add comment in `00_config.R` next to `CACHE_DIR` noting it is gitignored and must not be a repo-internal path

### Visualization Polish

- [ ] **VIZP-01**: Filter 1900 sentinel dates from all PPTX content (tables and graphs) so they never appear
- [ ] **VIZP-02**: New PPTX slide with summary table showing unique encounter dates per person by payer category, counted only after `max(LAST_CHEMO_DATE, LAST_RADIATION_DATE, LAST_SCT_DATE)`
- [ ] **VIZP-03**: Stacked encounter histograms by payer with post-treatment on bottom of each bar and pre-treatment on top, faceted by payer category

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
| TPAY-01 | Phase 8 | Complete |
| TPAY-02 | Phase 8 | Complete |
| TPAY-03 | Phase 8 | Complete |
| TXEXP-01 | Phase 9 | Complete |
| TXEXP-02 | Phase 9 | Complete |
| TXEXP-03 | Phase 9 | Complete |
| TXEXP-04 | Phase 9 | Complete |
| TXEXP-05 | Phase 9 | Complete |
| TXEXP-06 | Phase 9 | Complete |
| SURV-01 | Phase 10 | Complete |
| SURV-02 | Phase 10 | Complete |
| SURV-03 | Phase 10 | Complete |
| SURV-04 | Phase 10 | Complete |
| SVENC-01 | Phase 10 | Complete |
| SVENC-02 | Phase 10 | Complete |
| SVENC-03 | Phase 10 | Complete |
| SVENC-04 | Phase 10 | Complete |
| TDOC-01 | Phase 10 | Complete |
| TDOC-02 | Phase 10 | Complete |
| TDOC-03 | Phase 10 | Complete |
| PPTX-01 | Phase 11 | Complete |
| PPTX-02 | Phase 11 | Complete |
| PPTX-03 | Phase 11 | Complete |
| PPTX-04 | Phase 11 | Complete |
| PPTX-05 | Phase 11 | Complete |
| PPTX2-01 | Phase 12 | Complete |
| PPTX2-02 | Phase 12 | Complete |
| PPTX2-03 | Phase 12 | Complete |
| PPTX2-04 | Phase 17 | Pending |
| PPTX2-05 | Phase 12 | Complete |
| PPTX2-06 | Phase 12 | Complete |
| PPTX2-07 | Phase 17 | Pending |
| CSVAUDIT-01 | Phase 14 | Complete |
| CSVAUDIT-02 | Phase 14 | Complete |
| OPTIM-01 | Phase 14 | Complete |
| OPTIM-02 | Phase 14 | Complete |
| CACHE-01 | Phase 15 | Complete |
| CACHE-02 | Phase 15 | Complete |
| CACHE-03 | Phase 15 | Complete |
| CACHE-04 | Phase 15 | Complete |
| SNAP-01 | Phase 16 | Complete |
| SNAP-02 | Phase 16 | Complete |
| SNAP-03 | Phase 16 | Complete |
| SNAP-04 | Phase 16 | Complete |
| SNAP-05 | Phase 16 | Complete |
| GIT-01 | Phase 15 | Complete |
| GIT-02 | Phase 15 | Complete |
| VIZP-01 | Phase 17 | Pending |
| VIZP-02 | Phase 17 | Pending |
| VIZP-03 | Phase 17 | Pending |

**Coverage:**
- v1 requirements: 60 total
- Mapped to phases: 60
- Unmapped: 0

**v1.1 requirements:** 14 total
- Mapped to phases: 14
- Unmapped: 0

**Total coverage:** 74/74 requirements mapped (100%)

---
*Requirements defined: 2026-03-24*
*Last updated: 2026-04-02 after milestone v1.1 roadmap creation*
