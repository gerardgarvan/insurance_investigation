# Requirements: PCORnet Payer Variable Investigation (R Pipeline)

**Defined:** 2026-05-29
**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## v1.8 Requirements

Requirements for milestone v1.8 Episode-Level Cancer Linkage & First-Line Therapy Identification. Each maps to roadmap phases.

### Encounter Linkage

- [x] **LINK-01**: Cancer diagnosis linked to treatment episodes via ENCOUNTERID (direct match)
- [x] **LINK-02**: Temporal proximity fallback when ENCOUNTERID is NULL or missing (closest diagnosis within window)
- [x] **LINK-03**: HL flag derived from encounter-level diagnosis, not patient-level
- [x] **LINK-04**: Second cancer confirmation requires 2+ diagnoses 7 days apart (encounter-level)

### Treatment Validation

- [x] **TREAT-01**: SCT source audit — quantify how many SCT detections come from ICD DX codes only vs PROCEDURES/PRESCRIBING/DISPENSING
- [x] **TREAT-02**: Specific drug names resolved for each chemotherapy episode via RxNorm API (RXNORM_CUI/NDC → generic drug name)
- [x] **TREAT-03**: Drug name lookup table produced as standalone reference artifact
- [x] **TREAT-04**: Drug names carried through to Gantt episode output

### Regimen Identification

- [x] **REG-01**: Treatment episodes labeled with regimen name (ABVD, BV+AVD, Nivo+AVD) based on drug composition within 28-day cycle window
- [x] **REG-02**: Dropped-agent tolerance — ABVD with bleomycin dropped (→AVD) still classified as first-line
- [x] **REG-03**: Nothing added — ABVD+X is not ABVD
- [x] **REG-04**: Temporal availability rules — BV+AVD post-2019, Nivo+AVD post-2024

### First-Line Therapy

- [x] **FLT-01**: First-line therapy identified for adults 21+ at treatment date
- [x] **FLT-02**: 60-day clean period (no prior chemotherapy) defines first-line

### Death Analysis

- [x] **DEATH-01**: Death date analysis table — count of patients with death dates
- [x] **DEATH-02**: Of those with death dates, count where death is last encounter
- [x] **DEATH-03**: Count of patients with encounters/treatment after death date

### Output

- [x] **OUT-01**: New Gantt v2 output files (preserve existing v1 files)
- [x] **OUT-02**: Gantt v2 includes encounter-level cancer category, HL flag, and specific drug names

## v1.7 Requirements (Completed)

### Cancer Summary Refinement

- [x] **CREF-01**: Cancer summary table excludes benign neoplasm D-codes, retaining only malignant C-codes
- [x] **CREF-02**: Cancer summary table is regenerated after filtering cohort to patients with 2+ HL diagnosis codes at least 7 days apart (column F = 100% HL)
- [x] **CREF-03**: First HL diagnosis date is computed per patient from both DIAGNOSIS and TUMOR_REGISTRY tables (minimum date)
- [x] **CREF-04**: Cancer summary table is produced in two versions — all cancers and cancers occurring after first HL diagnosis date — for side-by-side comparison

### Gantt Enhancements

- [x] **GANTT-01**: Each treatment episode row in Gantt data includes cancer category label from CancerSiteCategories mapping (D-codes excluded)
- [x] **GANTT-02**: Each treatment episode row includes `is_hodgkin` binary column (TRUE when cancer category is Hodgkin Lymphoma)
- [x] **GANTT-03**: Death date from DEATH table is added to Gantt chart data as a treatment type for visualization

### Death Date Validation & Timeline

- [x] **DVAL-01**: Death dates occurring before a patient's earliest treatment date are identified and excluded as impossible
- [x] **DVAL-02**: Post-death clinical activity flagged per patient for manual review without auto-exclusion
- [x] **DVAL-03**: Patients with death dates but no treatment records are characterized
- [x] **DVAL-04**: HL Diagnosis pseudo-treatment rows appear in both gantt_episodes.csv and gantt_detail.csv
- [x] **DVAL-05**: Validated death dates artifact saved with death_valid and post_death_activity flags

## Future Requirements

Deferred to future milestone. Tracked but not in current roadmap.

### Visualization (carried from v1.0)

- **VIZ-01**: Produce attrition waterfall chart from filter log
- **VIZ-02**: Produce Sankey/alluvial stratified by payer
- **VIZ-03**: Apply HIPAA small-cell suppression in outputs

### Treatment Pipeline Extensions

- **EXT-01**: Treatment episode boundary formalization (45-day gap threshold)
- **EXT-02**: Multi-line therapy sequencing (first-line → second-line → third-line)
- **EXT-03**: Regimen expansion to other HL protocols (Stanford V, BEACOPP)
- **EXT-04**: Pediatric protocol regimen identification (age <21)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Statistical modeling / regression | Exploration only |
| Payer x treatment initiation timing analysis | v2 |
| Payer x diagnosis timing analysis | v2 |
| RMarkdown / Shiny rendering | v1 produces raw R scripts and PNG figures |
| Publication-ready figure formatting | Exploratory quality is sufficient |
| PREFIX_MAP centralization to R/00_config.R | Acceptable duplication; consider in future cleanup |
| Stanford V / BEACOPP regimen identification | Only 3 regimens (ABVD, BV+AVD, Nivo+AVD) cover ~95% of adult first-line |
| Pediatric protocols (age <21) | Adult protocols only for v1.8 |
| Multi-line therapy sequencing | Requires episode boundary formalization first |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| LINK-01 | Phase 61 | Complete |
| LINK-02 | Phase 61 | Complete |
| LINK-03 | Phase 61 | Complete |
| LINK-04 | Phase 61 | Complete |
| TREAT-01 | Phase 60 | Complete |
| TREAT-02 | Phase 60 | Complete |
| TREAT-03 | Phase 60 | Complete |
| TREAT-04 | Phase 60 | Complete |
| REG-01 | Phase 61 | Complete |
| REG-02 | Phase 61 | Complete |
| REG-03 | Phase 61 | Complete |
| REG-04 | Phase 61 | Complete |
| FLT-01 | Phase 62 | Complete |
| FLT-02 | Phase 62 | Complete |
| DEATH-01 | Phase 62 | Complete |
| DEATH-02 | Phase 62 | Complete |
| DEATH-03 | Phase 62 | Complete |
| OUT-01 | Phase 63 | Complete |
| OUT-02 | Phase 63 | Complete |

**Coverage:**
- v1.8 requirements: 19 total
- Mapped to phases: 19
- Unmapped: 0 (100% coverage)

---
*Requirements defined: 2026-05-29*
*Last updated: 2026-05-30 — Phase 61 complete (LINK-01 through LINK-04, REG-01 through REG-04)*
