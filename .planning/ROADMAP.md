# Roadmap: PCORnet Payer Variable Investigation (R Pipeline)

**Project:** PCORnet CDM Payer Analysis Pipeline (R)
**Created:** 2026-03-24
**Granularity:** Coarse (4 phases)
**Coverage:** 21/21 v1 requirements mapped

## Phases

- [x] **Phase 1: Foundation & Data Loading** - Configure paths, load 22 PCORnet CSV tables with correct data types, build utilities
- [x] **Phase 2: Payer Harmonization** - Implement 9-category payer mapping with encounter-level dual-eligible detection
- [x] **Phase 3: Cohort Building** - Build HL cohort using named filter predicates with attrition logging
- [ ] **Phase 4: Visualization** - Produce attrition waterfall and payer-stratified Sankey diagrams with HIPAA suppression

## Phase Details

### Phase 1: Foundation & Data Loading
**Goal**: User can load raw PCORnet CDM data with correct data types and configure analysis parameters

**Depends on**: Nothing (first phase)

**Requirements**: LOAD-01, LOAD-02, LOAD-03

**Success Criteria** (what must be TRUE):
1. User can load 22 PCORnet CSV tables (ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC + 16 others) into R with explicit column type specifications
2. User can parse dates in mixed SAS formats (DATE9, DATETIME, YYYYMMDD, Excel serial) with < 5% NA rate
3. User can configure file paths, ICD code lists (149 HL codes: 77 ICD-10 C81.xx + 72 ICD-9 201.xx), and payer mapping rules via `00_config.R`
4. User can access utility functions for attrition logging (`init_attrition_log()`, `log_attrition()`) and HIPAA suppression (primary + secondary suppression)

**Plans:** 2 plans

Plans:
- [x] 01-01-PLAN.md -- Config, scaffolding, date parser, attrition logger (LOAD-02, LOAD-03)
- [x] 01-02-PLAN.md -- PCORnet CSV loader with explicit col_types for 9 tables (LOAD-01)

---

### Phase 2: Payer Harmonization
**Goal**: User can harmonize payer data into 9 standard categories with encounter-level dual-eligible detection

**Depends on**: Phase 1 (requires loaded ENROLLMENT table and payer mapping config)

**Requirements**: PAYR-01, PAYR-02, PAYR-03

**Success Criteria** (what must be TRUE):
1. User can map raw PAYER_TYPE codes to 9 standard categories (Medicare, Medicaid, Dual eligible, Private, Other government, No payment/Self-pay, Other, Unavailable, Unknown) matching Python pipeline reference
2. User can identify dual-eligible patients via encounter-level detection (patients with Medicare+Medicaid cross-payer encounters or dual codes 14/141/142)
3. User can generate per-partner enrollment completeness report showing percentage of patients with enrollment records, mean enrollment duration, and gap patterns for each site (AMS, UMI, FLM, VRT)
4. User can validate payer harmonization output against Python pipeline counts (dual-eligible rate within 10-20% of Medicare + Medicaid combined)

**Plans:** 1 plan

Plans:
- [x] 02-01-PLAN.md -- ICD utility, 9-category payer mapping, dual-eligible detection, patient summary, enrollment completeness report (PAYR-01, PAYR-02, PAYR-03)

---

### Phase 3: Cohort Building
**Goal**: User can build HL cohort using named filter predicates with automatic attrition logging

**Depends on**: Phase 2 (requires harmonized payer categories and enrollment data)

**Requirements**: CHRT-01, CHRT-02, CHRT-03

**Success Criteria** (what must be TRUE):
1. User can apply named filter predicates (`has_hodgkin_diagnosis()`, `with_enrollment_period()`, `exclude_missing_payer()`) that read like clinical protocol steps
2. User can see N patients before and after every filter step via automatic attrition logging (accumulated into data frame with columns: step_name, n_before, n_after, n_excluded)
3. User can match HL diagnosis codes across both dotted (C81.10, 201.90) and undotted (C8110, 20190) ICD formats via normalization
4. User can generate final cohort dataset with all 149 HL codes identified, payer categories assigned, and enrollment periods validated

**Plans:** 2 plans

Plans:
- [x] 03-01-PLAN.md -- Treatment code config + named filter predicates and treatment flag functions (CHRT-01, CHRT-03)
- [x] 03-02-PLAN.md -- Cohort build pipeline with filter chain, attrition logging, and CSV output (CHRT-01, CHRT-02, CHRT-03)

---

### Phase 4: Visualization
**Goal**: User can visualize cohort attrition and payer-stratified patient flow

**Depends on**: Phase 3 (requires final cohort and attrition log)

**Requirements**: VIZ-01, VIZ-02, VIZ-03

**Success Criteria** (what must be TRUE):
1. User can produce attrition waterfall chart showing progressive cohort reduction through filter steps (vertical bars with N excluded at each step)
2. User can produce payer-stratified Sankey/alluvial diagram showing patient flow from payer category to treatment type, with flow thickness proportional to N patients and colored by payer category
3. User can verify HIPAA small-cell suppression is deferred to v2 per D-11 (exploratory outputs on HiPerGator)
4. User can save visualizations as PNG files (`output/figures/waterfall_attrition.png`, `output/figures/sankey_patient_flow.png`)

**Plans:** 1 plan

Plans:
- [x] 04-01-PLAN.md -- Waterfall attrition chart + payer-stratified Sankey diagram with colorblind-safe palette (VIZ-01, VIZ-02, VIZ-03)

---

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation & Data Loading | 2/2 | Complete | 2026-03-24 |
| 2. Payer Harmonization | 1/1 | Complete | 2026-03-24 |
| 3. Cohort Building | 2/2 | Complete | 2026-03-25 |
| 4. Visualization | 1/1 | Complete | 2026-03-25 |
| 5. Fix Parsing & HL Diagnosis Gaps | 2/3 | In Progress |  |
| 6. Use Debug Output to Rectify Issues | 3/3 | Complete | 2026-03-25 |
| 7. Dx Gap Analysis for Neither Patients | 0/1 | Planned |  |
| 8. Treatment-Anchored Payer Mode | 1/1 | Complete | 2026-03-26 |
| 9. Expand Treatment Detection | 3/3 | Complete | 2026-03-31 |
| 10. Surveillance, Survivorship & Documentation | 1/5 | In Progress|  |

## Next Actions

1. Execute `/gsd:execute-phase 10` to add surveillance, survivorship encounters, timing derivation, and auto-documentation

### Phase 5: Fix parsing of dates and other possible parsing errors and investigate why not everyone has an HL diagnosis

**Goal:** Fix date parsing and column detection issues across the pipeline, expand HL identification to include TUMOR_REGISTRY histology codes (ICD-O-3 9650-9667), and produce a reusable diagnostic script auditing data quality across all loaded tables
**Requirements**: FIX-01, FIX-02, FIX-03, FIX-04
**Depends on:** Phase 4 (builds on completed pipeline)
**Plans:** 2/3 plans executed

Plans:
- [x] 05-01-PLAN.md -- Config + utility fixes: ICD-O-3 histology codes, is_hl_histology(), expanded has_hodgkin_diagnosis(), date regex update (FIX-01, FIX-02, FIX-03)
- [x] 05-02-PLAN.md -- Reusable diagnostic script 07_diagnostics.R with 6 audit sections (FIX-01, FIX-02, FIX-03, FIX-04)
- [ ] 05-03-PLAN.md -- Cohort rebuild with expanded HL identification + human verification checkpoint (FIX-01, FIX-02)

### Phase 6: Use debug output to rectify issues

**Goal:** Take the diagnostic output from 07_diagnostics.R and use those findings to fix data quality issues across the pipeline: HL_SOURCE tracking, date parser expansion, col_types corrections, numeric validation, payer documentation, and full pipeline rebuild with data quality summary
**Requirements**: RECT-01, RECT-02, RECT-03, RECT-04, RECT-05
**Depends on:** Phase 5
**Plans:** 3/3 plans executed

Plans:
- [x] 06-01-PLAN.md -- HL_SOURCE tracking in cohort predicates + Neither exclusion with audit CSV (RECT-01, RECT-02)
- [x] 06-02-PLAN.md -- Data-driven fixes: date parser, regex, col_types, validation columns, payer docs (RECT-03, RECT-04)
- [x] 06-03-PLAN.md -- Diagnostics update, data quality summary script, full pipeline rebuild + verification (RECT-05)

### Phase 7: Dx gap analysis for excluded Neither patients

**Goal:** Investigate the 19 patients excluded as "Neither" (no HL evidence) to characterize the data gap by diagnosis history, enrollment, and tumor registry cross-reference, and determine whether the gap is closable or a data quality limitation
**Requirements**: GAP-01, GAP-02, GAP-03
**Depends on:** Phase 6
**Plans:** 1 plan

Plans:
- [ ] 07-01-PLAN.md -- Gap analysis script with diagnosis exploration, enrollment/TR cross-reference, gap classification, and pipeline decision checkpoint (GAP-01, GAP-02, GAP-03)

### Phase 8: Add insurance mode around three treatment types (chemo, radiation, stem cell) from procedures tables with plus/minus 30 days window

**Goal:** For each of three treatment types (chemotherapy, radiation, stem cell transplant), compute the patient's insurance payer mode within a +-30 day window around the first treatment procedure date, adding PAYER_AT_CHEMO, PAYER_AT_RADIATION, PAYER_AT_SCT columns (plus first treatment dates) to the existing hl_cohort output
**Requirements**: TPAY-01, TPAY-02, TPAY-03
**Depends on:** Phase 7
**Plans:** 1 plan

Plans:
- [x] 08-01-PLAN.md -- ICD procedure code config + treatment-anchored payer mode script + cohort integration (TPAY-01, TPAY-02, TPAY-03)

### Phase 9: Expand treatment detection using docx-specified tables and researched codes

**Goal:** Expand treatment detection for the existing 3 treatment types (chemotherapy, radiation, SCT) to cover all data sources specified in TreatmentVariables_2024.07.17.docx, adding DISPENSING, MED_ADMIN, DIAGNOSIS Z/V codes, ENCOUNTER DRG codes, and PROCEDURES revenue codes to both HAD_* flags and treatment-anchored payer computation
**Requirements**: TXEXP-01, TXEXP-02, TXEXP-03, TXEXP-04, TXEXP-05, TXEXP-06
**Depends on:** Phase 8
**Plans:** 3 plans

Plans:
- [x] 09-01-PLAN.md -- Expanded treatment code lists in config + DISPENSING/MED_ADMIN table loading (TXEXP-01, TXEXP-02, TXEXP-03, TXEXP-04)
- [x] 09-02-PLAN.md -- Expand has_chemo/radiation/sct() with DIAGNOSIS, DRG, DISPENSING, MED_ADMIN, revenue sources (TXEXP-01, TXEXP-02, TXEXP-03, TXEXP-04, TXEXP-05)
- [x] 09-03-PLAN.md -- Expand compute_payer_at_chemo/radiation/sct() date extraction with new sources (TXEXP-06)

### Phase 10: Incorporate VariableDetails.xlsx surveillance strategy and Treatment_Variable_Documentation.docx variables into pipeline, then regenerate Treatment_Variable_Documentation.docx

**Goal:** Add post-diagnosis surveillance modality detection (9 modalities + labs), survivorship encounter classification (4 levels), timing derivation variables (DAYS_DX_TO_*), and auto-generated comprehensive variable documentation covering the full pipeline output
**Requirements**: SURV-01, SURV-02, SURV-03, SURV-04, SVENC-01, SVENC-02, SVENC-03, SVENC-04, TDOC-01, TDOC-02, TDOC-03
**Depends on:** Phase 9
**Plans:** 1/5 plans executed

Plans:
- [ ] 10-01-PLAN.md -- Config code lists from VariableDetails.xlsx + LAB_RESULT_CM/PROVIDER table loading (SURV-01, SVENC-01)
- [ ] 10-02-PLAN.md -- Surveillance detection script 13_surveillance.R with 9 modalities + labs (SURV-02, SURV-03)
- [ ] 10-03-PLAN.md -- Survivorship encounter classification 14_survivorship_encounters.R with 4 levels (SVENC-02, SVENC-03)
- [ ] 10-04-PLAN.md -- Cohort integration: timing derivation + surveillance/survivorship joins in 04_build_cohort.R (SURV-04, SVENC-04, TDOC-01)
- [ ] 10-05-PLAN.md -- Auto-documentation generation 15_generate_documentation.R with .md and .docx output (TDOC-02, TDOC-03)

---

*Last updated: 2026-03-31*
