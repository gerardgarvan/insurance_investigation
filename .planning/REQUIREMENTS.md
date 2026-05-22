# Requirements: PCORnet Payer Variable Investigation (R Pipeline)

**Defined:** 2026-05-22
**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## v1.7 Requirements

Requirements for milestone v1.7 Cancer Summary Refinement & Gantt Enhancements. Each maps to roadmap phases.

### Cancer Summary Refinement

- [ ] **CREF-01**: Cancer summary table excludes benign neoplasm D-codes, retaining only malignant C-codes
- [ ] **CREF-02**: Cancer summary table is regenerated after filtering cohort to patients with 2+ HL diagnosis codes at least 7 days apart (column F = 100% HL)
- [ ] **CREF-03**: First HL diagnosis date is computed per patient from both DIAGNOSIS and TUMOR_REGISTRY tables (minimum date)
- [ ] **CREF-04**: Cancer summary table is produced in two versions — all cancers and cancers occurring after first HL diagnosis date — for side-by-side comparison

### Gantt Enhancements

- [ ] **GANTT-01**: Each treatment episode row in Gantt data includes cancer category label from CancerSiteCategories mapping (D-codes excluded)
- [ ] **GANTT-02**: Each treatment episode row includes `is_hodgkin` binary column (TRUE when cancer category is Hodgkin Lymphoma)
- [ ] **GANTT-03**: Death date from DEMOGRAPHIC table is added to Gantt chart data as a treatment type for visualization

## Future Requirements

Deferred to future milestone. Tracked but not in current roadmap.

### Visualization (carried from v1.0)

- **VIZ-01**: Produce attrition waterfall chart from filter log
- **VIZ-02**: Produce Sankey/alluvial stratified by payer
- **VIZ-03**: Apply HIPAA small-cell suppression in outputs

## Out of Scope

| Feature | Reason |
|---------|--------|
| Statistical modeling / regression | Exploration only |
| Payer x treatment initiation timing analysis | v2 |
| Payer x diagnosis timing analysis | v2 |
| RMarkdown / Shiny rendering | v1 produces raw R scripts and PNG figures |
| Publication-ready figure formatting | Exploratory quality is sufficient |
| PREFIX_MAP centralization to R/00_config.R | Acceptable duplication for v1.7; consider in future cleanup |
| In situ neoplasm (D00-D09) retention | All D-codes removed per user direction |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CREF-01 | — | Pending |
| CREF-02 | — | Pending |
| CREF-03 | — | Pending |
| CREF-04 | — | Pending |
| GANTT-01 | — | Pending |
| GANTT-02 | — | Pending |
| GANTT-03 | — | Pending |

**Coverage:**
- v1.7 requirements: 7 total
- Mapped to phases: 0
- Unmapped: 7

---
*Requirements defined: 2026-05-22*
*Last updated: 2026-05-22 after initial definition*
