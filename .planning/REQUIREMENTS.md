# Requirements: v3.3 Rituximab/Methotrexate-Associated Diagnoses of Interest

**Defined:** 2026-07-15
**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## Milestone Goal

Identify the non-malignant diagnoses that rituximab and methotrexate treat (autoimmune, inflammatory, hematologic), add them as a new "diagnosis of interest" (DoI) class distinct from the cancer cascade, and use them to disambiguate treatment attribution — flagging when a patient's rituximab/MTX **co-occurs with** a non-lymphoma condition. This is an additive, non-destructive layer; the cancer cascade and all existing outputs are read-only.

## v3.3 Requirements

### Diagnosis Code Set (DOI-CODE)

- [ ] **DOI-CODE-01**: A curated ICD-10-CM + ICD-9-CM code map for rituximab/methotrexate non-malignant indications (the 14 verified categories: RA, GPA/MPA vasculitis, pemphigus/pemphigoid, dermatomyositis/PM, SLE, Sjögren's, NMO/MG/optic neuritis, ITP/AIHA, psoriasis/PsA, Crohn's/IBD, plus edge conditions) is centralized in `R/00_config.R`, mirroring the `CANCER_SITE_MAP` structure (3-char / 4-char / individual-code keys)
- [ ] **DOI-CODE-02**: The known seed errors are excluded with inline documentation — I77.82 ("Dissection of artery", not vasculitis) and D47.Z2 (Castleman, already owned by the cancer cascade)
- [ ] **DOI-CODE-03**: Rituximab and methotrexate drug-code references and the `DOI_ATTRIBUTION_WINDOW_DAYS` constant are defined additively, without modifying `TREATMENT_CODES$chemo_rxnorm` or `DRUG_GROUPINGS` (no contamination of chemo/regimen detection)
- [ ] **DOI-CODE-04**: Each code group carries its clinical category, associated drug(s), and tier (table-stakes vs edge) so downstream outputs can label and filter by confidence

### Classification (DOI-CLASS)

- [x] **DOI-CLASS-01**: `is_doi_code()` and `classify_doi_codes()` utilities live in a new `R/utils/utils_doi.R`, DX_TYPE-gated (ICD-9 `09` vs ICD-10 `10`, NA/SNOMED → FALSE), structurally mirroring `is_cancer_code()` / `classify_codes()`
- [x] **DOI-CLASS-02**: An encounter-level diagnosis-of-interest flag + category is produced, guaranteed non-overlapping with the cancer categories
- [ ] **DOI-CLASS-03**: A patient-level diagnosis-of-interest summary is derived from the encounter grain
- [x] **DOI-CLASS-04**: A mutual-exclusivity hard-stop assertion (`sum(is_doi_code(DX) & is_cancer_code(DX)) == 0`) runs before any output is produced and halts the script if it fires
- [x] **DOI-CLASS-05**: L10.81 (paraneoplastic pemphigus) encounters carry a `paraneoplastic_flag` so cancer-associated pemphigus is distinguishable from primary autoimmune pemphigus

### Attribution Linkage (DOI-ATTR)

- [ ] **DOI-ATTR-01**: A two-tier linkage joins rituximab/MTX administrations to DoI diagnoses — ENCOUNTERID direct match first, then a ±90-day PATID temporal window (window value defensible and documented)
- [ ] **DOI-ATTR-02**: A three-state `likely_non_lymphoma_directed` flag (TRUE / FALSE / NA) carries the analytic signal, where NA explicitly marks the ambiguous case (HL also active in the same window)
- [ ] **DOI-ATTR-03**: An `attribution_method` column records how each link was made (encounter_id / temporal_window / none); all column names and prose use co-occurrence language ("with [dx]"), never causal ("for [dx]")

### Output / Report (DOI-OUT)

- [ ] **DOI-OUT-01**: A Tableau-ready multi-sheet xlsx is produced (patient prevalence, encounter co-occurrence, drug × DoI summary, metadata), following the R/100+ investigation-script convention
- [ ] **DOI-OUT-02**: DoI outputs are internal investigation outputs — raw counts, NO automated small-cell suppression; each output carries an "internal-only; suppress manually before external sharing" note (relaxed per Phase 127 D-07, consistent with the v3.1 internal-investigation pattern)
- [ ] **DOI-OUT-03**: The metadata sheet documents the attribution window (with ±30/±180-day sensitivity comparison) and every sheet carries the CAVEATS footnote that co-occurrence does not imply attribution

### Registration & Validation (DOI-QA)

- [ ] **DOI-QA-01**: The new investigation script is registered in `R/39_run_all_investigations.R` and gets a `R/SCRIPT_INDEX.md` row
- [ ] **DOI-QA-02**: A new `R/88_smoke_test_comprehensive.R` section validates the DoI layer, including the mutual-exclusivity hard-stop check
- [ ] **DOI-QA-03**: HiPerGator runtime confirmation (real DIAGNOSIS table, DoI hit counts logged) is recorded as the definition-of-done gate
- [x] **DOI-QA-04**: The local test fixture is augmented with at least one ICD-10 and one ICD-9 DoI patient so the classifier is exercised locally

## Future Requirements

Deferred to a later milestone. Tracked but not in the current roadmap.

### Payer/Attribution Analytics (DOI-FUT)

- **DOI-FUT-01**: Payer-stratified DoI co-occurrence (which insurance categories carry which autoimmune burden)
- **DOI-FUT-02**: Dose/route disambiguation for methotrexate (high-dose IV oncologic vs low-dose oral autoimmune) using PRESCRIBING/MED_ADMIN dose fields
- **DOI-FUT-03**: Cohort-level attrition impact — reclassify treatment episodes flagged as likely non-lymphoma-directed and quantify the effect on regimen/first-line counts

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Claiming causal attribution ("rituximab was FOR the RA") | Administrative claims data proves co-occurrence only; causal attribution requires chart review |
| Adding rituximab CUIs to `TREATMENT_CODES$chemo_rxnorm` | Would inflate chemo detection and corrupt ABVD/BV+AVD regimen identification |
| Modifying the cancer cascade (`utils_cancer.R`, `CANCER_SITE_MAP`, R/28) | DoI is a parallel read-only layer; cancer classification is unchanged |
| New R packages (`icd`, `comorbidity`, `touch`) | The existing `classify_codes()` prefix-cascade pattern fully suffices; no new dependencies |
| EGPA (M30.1) as a confident indication | Mepolizumab is now FDA-preferred; rituximab is off-label — included only as low-confidence edge |
| Real-time RxNorm API calls for CUI discovery | CUIs curated once offline and pinned in config |

## Traceability

Which phases cover which requirements. Populated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| DOI-CODE-01 | Phase 127 | Pending |
| DOI-CODE-02 | Phase 127 | Pending |
| DOI-CODE-03 | Phase 127 | Pending |
| DOI-CODE-04 | Phase 127 | Pending |
| DOI-CLASS-01 | Phase 127 | Complete |
| DOI-CLASS-02 | Phase 128 | Complete |
| DOI-CLASS-03 | Phase 128 | Pending |
| DOI-CLASS-04 | Phase 128 | Complete |
| DOI-CLASS-05 | Phase 128 | Complete |
| DOI-ATTR-01 | Phase 129 | Pending |
| DOI-ATTR-02 | Phase 129 | Pending |
| DOI-ATTR-03 | Phase 129 | Pending |
| DOI-OUT-01 | Phase 129 | Pending |
| DOI-OUT-02 | Phase 129 | Pending |
| DOI-OUT-03 | Phase 129 | Pending |
| DOI-QA-01 | Phase 130 | Pending |
| DOI-QA-02 | Phase 130 | Pending |
| DOI-QA-03 | Phase 130 | Pending |
| DOI-QA-04 | Phase 127 | Complete |

**Coverage:**
- v3.3 requirements: 19 total
- Mapped to phases: 19 (roadmap complete)
- Unmapped: 0 ✓

---
*Requirements defined: 2026-07-15*
*Last updated: 2026-07-15 after roadmap creation — all 19 requirements mapped*
