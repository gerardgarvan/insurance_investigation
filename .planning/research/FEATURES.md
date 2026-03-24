# Feature Landscape

**Domain:** PCORnet CDM cohort-building and payer analysis pipeline (R)
**Researched:** 2026-03-24

## Table Stakes

Features users expect. Missing = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| PCORnet CDM table loading | Core requirement for any PCORnet analysis — without loading ENROLLMENT, DIAGNOSIS, PROCEDURES, DEMOGRAPHIC tables, no analysis possible | Low-Medium | Must handle 22+ CSV tables with correct data types. Requires file path configuration. |
| ICD code matching (ICD-9 + ICD-10) | Clinical cohort definition requires both historical (ICD-9) and current (ICD-10) codes; ICD-9-to-ICD-10 transition happened 2015 | Medium | Must handle both dotted (C81.00) and undotted (C8100) formats. 149 HL codes: 77 ICD-10 (C81.xx), 72 ICD-9 (201.xx). |
| Named filter predicates | Reproducibility and auditability requirement — opaque one-liners make cohort definitions impossible to validate or replicate | Low | Functions like `has_diagnosis()`, `with_enrollment()`, `exclude_missing_values()` read like clinical protocol. |
| Attrition logging | Table stakes for any cohort study — CONSORT diagrams and transparency standards require documenting exclusions at each step | Low | Log "N before" and "N after" for every filter operation automatically. Essential for study validity. |
| Attrition waterfall visualization | Standard presentation format for cohort studies — papers and IRBs expect CONSORT-style flow diagrams | Medium | Vertical bar chart showing progressive cohort reduction through exclusion criteria. |
| HIPAA small-cell suppression | Legal requirement, not optional — counts 1-10 must be suppressed in any research output using patient data | Low | Standard threshold: suppress cells with N ≤ 10. Secondary suppression may be needed to prevent inference. |
| Multi-site data handling | PCORnet infrastructure is inherently multi-site — data provenance and site-level quality differences are fundamental to the network | Medium | OneFlorida+ has partner-level differences: claims-only (FLM), mapped EHR (AMS, UMI), death-only (VRT). Site ID must be preserved. |
| Payer harmonization (basic) | PCORnet studies routinely investigate insurance disparities — without standardized payer categories, cross-study comparisons fail | Medium | Must map raw payer codes to standard categories. Minimum: Medicare, Medicaid, Private, Other/Unknown. |
| Data type enforcement | PCORnet CDM has strict data types (DATE, INTEGER, VARCHAR) — loading with wrong types causes silent errors in date arithmetic and joins | Low | Dates as Date, IDs as character, counts as integer. Config-driven type specification. |
| Encounter-based enrollment | PCORnet CDM defines enrollment as periods when events are observable — without this, cohort inclusion criteria misidentify "no diagnosis" vs "no observation window" | Medium | ENROLLMENT table or encounter-based algorithm. Critical for attrition calculations. |

## Differentiators

Features that set product apart. Not expected, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Dual-eligible detection | Most payer analyses treat Medicare and Medicaid as separate — dual-eligible patients (Medicare + Medicaid simultaneously) have unique barriers and outcomes | High | Requires time-aware logic: same patient with overlapping Medicare + Medicaid enrollment periods = dual-eligible. 8.7M full-benefit duals in 2019. |
| Sankey/alluvial visualization stratified by payer | Standard analysis shows patient flow; stratifying by payer reveals insurance-driven pathway differences that bar charts miss | High | ggalluvial package. Shows enrollment → diagnosis → treatment with flow thickness proportional to N patients, colored by payer category. |
| Payer harmonization (9-category with dual-eligible) | Basic payer mapping lumps disparate groups; 9-category system including dual-eligible enables nuanced disparity investigation | High | Medicare, Medicaid, Dual eligible, Private, Other government, No payment/Self-pay, Other, Unavailable, Unknown. Matches established Python pipeline for cross-tool validation. |
| Filter chain provenance tracking | Standard logging shows attrition; provenance tracking shows *which predicates were applied in which order*, enabling replication and debugging | Medium | Each filter step records predicate name, parameters, timestamp. Creates reproducible audit trail. |
| Human-readable filter predicate names | Most pipelines use inline `filter()` with complex boolean logic; named predicates make cohort definition self-documenting | Low | `has_hodgkin_lymphoma_diagnosis()` beats `filter(dx %in% c("C81.00", "C81.01", ...))`. Code reads like methods section. |
| Site-level data quality reporting | Multi-site data has site-specific completeness issues; flagging which sites contribute diagnosis vs procedure codes identifies bias sources | Medium | Per-site summary: N patients, diagnosis code completeness, procedure code completeness, enrollment method (claims vs EHR vs encounter-based). |
| ICD code version metadata | ICD-9/ICD-10 transition creates temporal bias — tagging which codes/years use which version enables sensitivity analysis | Medium | Track: which diagnosis codes are ICD-9 vs ICD-10, date ranges for each, proportion of cohort identified by each version. |
| Configuration-driven paths | Hard-coded paths break on different HPC systems; config-driven paths enable replication across institutions and environments | Low | `R/00_config.R` with paths to CSVs, output directories. One file to change for new environment. |
| Treatment timing windows | Payer analysis often focuses on whether patients receive treatment; *when* treatment starts reveals insurance-driven delays | Medium | Out of scope for v1, but differentiator for v2. Calculate days from diagnosis to first treatment, stratified by payer. |
| Missing data audit by site and year | Completeness varies by site and time; systematic audit reveals whether findings reflect true patterns or data artifacts | High | Out of scope for v1. Per-site, per-year heatmap of completeness for key variables (diagnosis, procedures, enrollment, payer). |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Statistical modeling / regression | Premature — without validated cohort and clean visualizations, modeling findings are uninterpretable | Build cohort + viz first. Validate N patients, attrition logic, payer mapping. Model in v2 after exploration. |
| Replicating Python pipeline's data cleaning | Two pipelines with different cleaning logic = divergent cohort definitions that can't be compared | R pipeline loads *raw* CSVs and applies its own filter chain. Python pipeline is reference for payer logic only, not data cleaning. |
| Publication-ready figure formatting | Premature optimization — exploratory figures clarify patterns; polishing aesthetics before validating substance wastes time | PNG output at exploratory quality. Titles, labels, legends present but not publication-formatted. Save polish for validated findings. |
| Interactive visualizations (Shiny) | Adds complexity and deployment overhead without enabling additional exploration for single-analyst use | Static R scripts + PNG output. Shiny deferred to v2 if multi-user access becomes requirement. |
| RMarkdown report generation | Report infrastructure before validated findings = boilerplate without substance | Raw R scripts (.R files) that produce figures. RMarkdown in v2 after stabilizing analysis. |
| Real-time data integration | PCORnet data refreshes quarterly; real-time integration adds complexity without enabling new analyses | Load static CSV extracts from HiPerGator filesystem. Refresh = re-run pipeline on new extract. |
| Cross-CDM harmonization (OMOP, i2b2) | Scope creep — PCORnet CDM only for this study | Single CDM. PCORnet v7.0 specification. No cross-CDM mapping. |
| De-identification beyond small-cell suppression | Over-engineering — HiPerGator is HIPAA-compliant environment; data stays on secure system | Small-cell suppression for outputs. No additional de-identification (k-anonymity, differential privacy). |
| Custom ICD code grouping beyond HL | Feature creep — 149 HL codes are study-specific; building general ICD grouper is separate project | Hard-code 149 HL codes (77 ICD-10, 72 ICD-9). No CCS, CCSR, or other grouping systems. |
| Version control for data files | PCORnet extracts are multi-GB; versioning data in Git breaks repository | Version control for *code* only (.R scripts, config). Data files referenced by extract date in config. |

## Feature Dependencies

```
PCORnet CDM table loading
  └─> Data type enforcement (dates, IDs load correctly)
  └─> Multi-site data handling (site IDs preserved)
       └─> Site-level data quality reporting (requires site ID)

ICD code matching (ICD-9 + ICD-10)
  └─> ICD code version metadata (optional but valuable)

Named filter predicates
  └─> Attrition logging (each predicate logs N before/after)
       └─> Attrition waterfall visualization (visualizes logged attrition)
  └─> Filter chain provenance tracking (records which predicates applied when)

Encounter-based enrollment
  └─> Named filter predicates (enrollment check is a predicate)

Payer harmonization (basic)
  └─> Dual-eligible detection (requires temporal overlap detection)
       └─> Payer harmonization (9-category) (dual-eligible is 3rd category)

Payer harmonization (9-category)
  └─> Sankey/alluvial visualization stratified by payer (stratification requires clean categories)

Configuration-driven paths
  └─> PCORnet CDM table loading (paths specified in config)
```

## MVP Recommendation

Prioritize:
1. **PCORnet CDM table loading** with data type enforcement and configuration-driven paths
2. **ICD code matching** (ICD-9 + ICD-10, dotted + undotted formats) for 149 HL codes
3. **Named filter predicates** with automatic attrition logging
4. **Attrition waterfall visualization** from logged filter chain
5. **Payer harmonization (9-category with dual-eligible)** matching Python pipeline
6. **Sankey/alluvial visualization** stratified by payer
7. **HIPAA small-cell suppression** in all outputs
8. **Multi-site data handling** preserving site provenance

Defer:
- **Site-level data quality reporting**: Build after validating basic pipeline — site-specific issues will surface naturally during exploration
- **ICD code version metadata**: Nice-to-have for sensitivity analysis, but not required for initial cohort validation
- **Filter chain provenance tracking**: Enhanced audit trail is valuable but attrition logging provides minimum transparency
- **Treatment timing windows**: Out of scope for v1 per PROJECT.md — payer × timing analysis is v2
- **Missing data audit by site and year**: Out of scope for v1 — comprehensive QA is v2 after establishing baseline findings

**Rationale for MVP:**
- **Table stakes first**: Loading, filtering, visualization are non-negotiable for any cohort study
- **Differentiators that enable study goals**: Dual-eligible detection and payer-stratified Sankey directly address insurance disparity investigation
- **Defer complexity without blocking validation**: Site-level QA and provenance enhancements can be added after confirming cohort logic works

## Feature Complexity Notes

### Low Complexity (1-2 days)
- Data type enforcement: CSVs with `col_types` specification
- Named filter predicates: Wrapper functions around `dplyr::filter()`
- Attrition logging: Print N before/after each filter step
- HIPAA small-cell suppression: `if (n <= 10) NA_integer_` in output generation
- Configuration-driven paths: `config.R` with path variables
- Human-readable filter predicate names: Naming convention only

### Medium Complexity (3-5 days)
- PCORnet CDM table loading: 22 tables × data type specs × validation checks
- ICD code matching: 149 codes × 2 formats (dotted, undotted) × regex patterns
- Attrition waterfall visualization: ggplot2 waterfall from log data
- Multi-site data handling: Preserve site ID through pipeline, document site-specific characteristics
- Payer harmonization (basic): Mapping raw enrollment payer codes to 4-6 standard categories
- Encounter-based enrollment: ENROLLMENT table logic or encounter-based algorithm
- Filter chain provenance tracking: Data structure tracking predicate names, params, timestamps
- Site-level data quality reporting: Per-site summary tables of completeness
- ICD code version metadata: Flag diagnosis records as ICD-9 vs ICD-10 based on date and code format

### High Complexity (1-2 weeks)
- Dual-eligible detection: Time-aware enrollment overlap detection (Medicare + Medicaid simultaneous periods)
- Payer harmonization (9-category with dual-eligible): 9-way mapping + temporal dual detection + validation against Python pipeline reference
- Sankey/alluvial visualization stratified by payer: ggalluvial data reshaping + stratification + small-cell suppression in flows
- Treatment timing windows: Identify first treatment after diagnosis per patient, calculate time deltas, handle missing data
- Missing data audit by site and year: Per-site × per-year × per-variable completeness matrix + visualization

## Sources

### PCORnet Infrastructure and CDM
- [PCORnet Common Data Model](https://pcornet.org/data/common-data-model/)
- [PCORnet CDM v7.0 Specification](https://pcornet.org/wp-content/uploads/2025/05/PCORnet_Common_Data_Model_v70_2025_05_01.pdf)
- [PCORnet Data Curation](https://pcornet.org/news/category/data-resource/data-curation/)
- [CDM Guidance Repository (GitHub)](https://github.com/CDMFORUM/CDM-GUIDANCE)

### Data Quality and Harmonization
- [Evaluating Foundational Data Quality in PCORnet (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC5983028/)
- [Tailoring Rule-Based Data Quality Assessment to PCORnet CDM (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC10148276/)
- [Harmonization of Common Data Models and Open Standards (ASPE)](https://aspe.hhs.gov/harmonization-various-common-data-models-open-standards-evidence-generation)
- [Multi-Site Data Harmonization (Chapter 6, Informatics Playbook)](https://playbook.cd2h.org/en/latest/chapters/chapter_6.html)

### Cohort Building and Attrition Visualization
- [Visualizations in Pharmacoepidemiology Study Planning (Wiley)](https://onlinelibrary.wiley.com/doi/10.1002/pds.5529)
- [dtrackr - CONSORT Statement Example (CRAN)](https://cran.r-project.org/web/packages/dtrackr/vignettes/consort-example.html)
- [Cohort Data Management Systems Scoping Review (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC12619332/)

### Sankey/Alluvial Diagrams
- [Overview of Sankey Flow Diagrams in Clinical Research (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC9232856/)
- [Exploring Patient Path Through Sankey Diagram (PubMed)](https://pubmed.ncbi.nlm.nih.gov/32570378/)
- [ggalluvial: Layered Grammar for Alluvial Plots (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC10010671/)
- [ggalluvial Documentation](https://corybrunson.github.io/ggalluvial/)

### Payer Analysis and Dual Eligibility
- [Identifying Dual Eligible Medicare Beneficiaries (ResDAC)](https://resdac.org/articles/identifying-dual-eligible-medicare-beneficiaries-medicare-beneficiary-enrollment-files)
- [Medicare-Medicaid Dual Enrollment Data Brief (CMS)](https://www.cms.gov/files/document/medicaremedicaiddualenrollmenteverenrolledtrendsdatabrief.pdf)
- [State All Payer Claims Databases (ASPE)](https://aspe.hhs.gov/reports/state-all-payer-claims-databases-pcorf-multi-state-studies)
- [Enhancing PCORnet Data with Insurance Claims (PubMed)](https://pubmed.ncbi.nlm.nih.gov/34897506/)

### ICD Codes and Clinical Coding
- [ICD-10-CM Codes C81: Hodgkin Lymphoma](https://www.icd10data.com/ICD10CM/Codes/C00-D49/C81-C96/C81-)
- [Validation of Electronic Algorithm for Lymphoma in ICD-10-CM (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC8205565/)
- [ICD-9-CM to ICD-10-CM General Equivalence Mappings (CMS)](https://www.cms.gov/files/document/diagnosis-code-set-general-equivalence-mappings-icd-10-cm-icd-9-cm-and-icd-9-cm-icd-10-cm.pdf)

### HIPAA and Privacy
- [CMS Cell Size Suppression Policy (ResDAC)](https://resdac.org/articles/cms-cell-size-suppression-policy)
- [Department of Health Agency Standards for Reporting Data with Small Numbers (WA DOH)](https://www.doh.wa.gov/portals/1/documents/1500/smallnumbers.pdf)
- [HIPAA Privacy Rule and Research (HHS.gov)](https://www.hhs.gov/hipaa/for-professionals/special-topics/research/index.html)

### Reproducible Research and Configuration Management
- [Reproducible Analytical Pipelines (Government Analysis Function)](https://analysisfunction.civilservice.gov.uk/support/reproducible-analytical-pipelines/)
- [Building Trustworthy AI: Reproducible Pipelines and Audit Trails (Medium)](https://medium.com/prompt-engineering/building-trustworthy-ai-the-importance-of-reproducible-analytical-pipelines-and-audit-trails-for-d85a34e9cad2)
- [Development of HIPAA-Compliant Environment for Research (PMC)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3912719/)

### Claims vs EHR Data
- [Claims Data vs EHRs in Real-World Research (Nashville Biosciences)](https://nashbio.com/blog/ehr/claims-data-vs-ehrs/)
- [Electronic Health Records vs Medicaid Claims Completeness (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC3133583/)
