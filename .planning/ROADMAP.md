# Roadmap: PCORnet Payer Variable Investigation (R Pipeline)

**Project:** PCORnet CDM Payer Analysis Pipeline (R)
**Created:** 2026-03-24
**Granularity:** Coarse (4 phases)
**Coverage:** 12/12 v1 requirements mapped

## Phases

- [x] **Phase 1: Foundation & Data Loading** - Configure paths, load 22 PCORnet CSV tables with correct data types, build utilities
- [x] **Phase 2: Payer Harmonization** - Implement 9-category payer mapping with encounter-level dual-eligible detection
- [ ] **Phase 3: Cohort Building** - Build HL cohort using named filter predicates with attrition logging
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
- [ ] 03-02-PLAN.md -- Cohort build pipeline with filter chain, attrition logging, and CSV output (CHRT-01, CHRT-02, CHRT-03)

---

### Phase 4: Visualization
**Goal**: User can visualize cohort attrition and payer-stratified patient flow with HIPAA-compliant suppression

**Depends on**: Phase 3 (requires final cohort and attrition log)

**Requirements**: VIZ-01, VIZ-02, VIZ-03

**Success Criteria** (what must be TRUE):
1. User can produce attrition waterfall chart showing progressive cohort reduction through filter steps (vertical bars with N excluded at each step)
2. User can produce payer-stratified Sankey/alluvial diagram showing patient flow from enrollment -> diagnosis -> treatment, with flow thickness proportional to N patients and colored by payer category
3. User can verify all outputs apply HIPAA small-cell suppression (counts 1-10 replaced with "<11" with secondary suppression to prevent back-calculation)
4. User can save visualizations as PNG files (`output/figures/waterfall_attrition.png`, `output/figures/sankey_patient_flow.png`)

**Plans**: TBD

---

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation & Data Loading | 2/2 | Complete | 2026-03-24 |
| 2. Payer Harmonization | 1/1 | Complete | 2026-03-24 |
| 3. Cohort Building | 0/2 | Planned | - |
| 4. Visualization | 0/? | Not started | - |

## Next Actions

1. Execute `/gsd:execute-phase 3` to build HL cohort

---

*Last updated: 2026-03-24*
