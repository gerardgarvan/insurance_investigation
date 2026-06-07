# Feature Landscape: Gantt Data Enrichment for Oncology Treatment Episodes

**Domain:** Oncology treatment timeline data enrichment
**Researched:** 2026-06-07
**Confidence:** MEDIUM (WebSearch-based ecosystem understanding + existing pipeline context)

## Table Stakes

Features users expect. Missing = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Treatment line classification (F/S/E/N) | Standard oncology nomenclature used by NCCN and ASCO; clinicians expect "first-line", "second-line", "salvage" labels for treatment sequencing | Medium | Requires temporal ordering logic + clean period detection (already have 60-day clean period for first-line); N=newly diagnosed, F=first-line, S=second-line, E=salvage/expanded access |
| Human-readable medication names | RxNorm codes alone are meaningless to clinicians; need generic names (e.g., "Doxorubicin" not "224905") for treatment interpretation | Low | Already have RxNorm API resolution (Phase 60); xlsx column C has curated names; straight lookup |
| Code type metadata (RXNORM/CPT/HCPCS/ICD-10-CM) | Essential for data provenance and code interpretation; different code systems have different clinical meanings | Low | Deterministic from code structure + source table; PCORnet CDM uses RXNORM (PRESCRIBING), CPT/HCPCS (PROCEDURES), ICD-10-CM (DIAGNOSIS) |
| Source table metadata (PRESCRIBING/PROCEDURES/DIAGNOSIS) | Required for understanding data origin, verifying code usage context, and debugging false positives | Low | Already tracked during treatment detection; straight passthrough from existing logic |
| SCT conditioning/immunotherapy cross-use flags | SCT codes often dual-purpose (conditioning regimen vs immunotherapy); flag prevents misclassification of treatment intent | Medium | Based on xlsx column 9; requires code-level lookup; affects episode categorization when SCT codes appear outside transplant context |
| False-positive SCT code removal | Status/complication codes (Z94.84 "transplant status", T86.5 "complications") mistaken for procedure codes; inflate treatment counts if not excluded | Low | Hard-coded exclusion list (5 codes identified); add to existing code filtering logic |
| Questionable immunotherapy code flagging | Vitamin combinations (8 codes) and CAR-T classification ambiguity (2 codes) need manual review flags for clinical validation | Low | Binary flag column; does not remove codes, just marks for downstream review |

## Differentiators

Features that set product apart. Not expected, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Per-code line classification (not just per-episode) | Existing `is_first_line` applies to whole regimen; per-code granularity enables mixed-line episode detection (e.g., salvage + first-line overlap) | Medium | Dependency on existing is_first_line logic; per-code level adds episode complexity but enables richer analysis |
| Episode-level drug group enrichment | Already have drug grouping tables (Phase 88); adding to Gantt CSV links treatment codes to therapeutic categories (anthracyclines, alkylators, etc.) | Low-Medium | Requires join on code; enhances clinical interpretation; differentiates from raw code lists |
| Treatment line trajectory visualization | Gantt charts colored/stratified by F/S/E/N labels enable quick visual detection of treatment escalation patterns | Medium | Requires ggplot2 layer modification; complements existing Gantt v2 CSV output |
| Code validation status column | Flags codes that passed/failed xlsx cross-reference lookup; surfaces data quality issues for manual review | Low | Low confidence codes get flagged; helps identify codes needing curation in future xlsx updates |
| Multi-source code deduplication tracking | When same treatment appears in PRESCRIBING + DISPENSING, track both sources; enables EHR completeness analysis | Low | Existing overlap detection (Phase 33); extend to treatment codes with source concatenation |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Automated treatment line inference without clean period validation | Treatment line sequencing requires clinical context (intent, response, progression); algorithmic guessing introduces false classifications | Rely on F/S/E/N labels from xlsx (curated by domain experts); use temporal clean period only for first-line confirmation |
| Per-patient line numbering (line 1, line 2, line 3...) | Multi-line sequencing out of scope (PROJECT.md line 96); requires episode boundary formalization not yet completed | Stop at F/S/E/N categorical labels; defer sequential numbering to v3.x when episode boundaries finalized |
| Medication name resolution for non-chemotherapy | PROJECT.md line 283: "Drug name resolution for chemotherapy only"; radiation, surgery, SCT identified adequately by code alone | Keep medication names blank for non-PRESCRIBING codes; avoid RxNorm API calls for CPT/HCPCS |
| Code type auto-detection from external APIs | Adds runtime dependency + failure mode; PCORnet CDM table structure already encodes code type (RXNORM in PRESCRIBING, CPT/HCPCS in PROCEDURES, ICD in DIAGNOSIS) | Deterministic lookup from source table + code format patterns |
| Real-time xlsx updates during pipeline run | Introduces file I/O race conditions + versioning ambiguity; xlsx is static reference, not live database | Load xlsx once at script start; treat as immutable lookup table; version control xlsx separately |
| Treatment line prediction for pediatric protocols | PROJECT.md line 95: "Pediatric protocols (age <21) — adult protocols only for v1.x" | F/S/E/N classification applies only to adult patients; filter or flag pediatric cases (age <21) |

## Feature Dependencies

```
False-positive SCT code removal → SCT detection logic (Phase 60)
Treatment line classification (F/S/E/N) → is_first_line logic (Phase 62)
Per-code line classification → Episode construction (Phase 60)
Medication names → RxNorm API resolution (Phase 60)
Code type metadata → Source table tracking (Phase 60)
Source table metadata → Treatment detection (Phase 9)
SCT cross-use flags → xlsx column 9 data
Questionable immunotherapy flags → xlsx annotation column
Drug group enrichment → Drug grouping tables (Phase 88)
```

## MVP Recommendation

### Prioritize (Table Stakes First)

1. **Medication names** (Low complexity, high clinical value; straight lookup from xlsx column C)
2. **Code type + source table metadata** (Low complexity, required for provenance; deterministic from existing data)
3. **False-positive SCT code removal** (Low complexity, fixes data quality issue; 5-code exclusion list)
4. **Treatment line classification (F/S/E/N)** (Medium complexity, table stakes nomenclature; extends existing is_first_line)
5. **SCT conditioning/immunotherapy cross-use flags** (Medium complexity, prevents misclassification; xlsx column 9 lookup)
6. **Questionable immunotherapy code flagging** (Low complexity, enables validation; 10-code flagging list)

### Defer to v2.4+

- **Per-code line classification** (dependency on episode formalization; multi-line sequencing out of scope for v2.3)
- **Episode-level drug group enrichment** (nice-to-have; drug grouping tables already exist as separate output)
- **Treatment line trajectory visualization** (ggplot2 modification; can be done post-export with existing CSV data)
- **Code validation status column** (low priority; manual xlsx curation workflow not formalized yet)
- **Multi-source code deduplication tracking** (overlap analysis pattern exists but not integrated into Gantt output)

## Implementation Notes

### Treatment Line Classification Approach

**Option 1: Extend is_first_line logic**
- Existing: Boolean `is_first_line` at regimen level (60-day clean period, ABVD/BV+AVD/Nivo+AVD)
- Extension: Add `treatment_line` categorical column (F/S/E/N) based on clean period + xlsx annotation
- Pros: Reuses validated clean period logic
- Cons: Still regimen-level, not per-code

**Option 2: Per-code temporal ordering**
- Assign F/S/E/N based on code appearance order within patient + xlsx metadata
- Pros: Granular per-code classification
- Cons: Requires episode boundary formalization (deferred to v3.x)

**Recommendation for v2.3:** Option 1 — extend regimen-level classification with F/S/E/N categories from xlsx, keep per-code deferred.

### Code Type Determination Logic

```r
determine_code_type <- function(code, source_table) {
  case_when(
    source_table == "PRESCRIBING" ~ "RXNORM",
    source_table == "PROCEDURES" & str_detect(code, "^[0-9]{5}$") ~ "CPT",
    source_table == "PROCEDURES" & str_detect(code, "^[A-Z][0-9]{4}$") ~ "HCPCS",
    source_table == "DIAGNOSIS" ~ "ICD-10-CM",
    TRUE ~ "UNKNOWN"
  )
}
```

### False-Positive SCT Code Exclusion List

```r
# Status/complication codes (NOT procedures)
FALSE_POSITIVE_SCT_CODES <- c(
  "Z94.84",  # Stem cells transplant status
  "T86.5",   # Complications of stem cell transplant
  # Additional 3 codes from xlsx investigation
)
```

### Questionable Immunotherapy Flag List

```r
# Vitamin combinations (8 codes) + CAR-T classification TBD (2 codes)
QUESTIONABLE_IMMUNOTHERAPY_CODES <- c(
  # 8 vitamin combo codes from xlsx
  # 2 CAR-T codes pending classification
)
```

## Data Quality Considerations

### Known Pitfalls

1. **Treatment line ambiguity:** Second-line vs salvage terminology varies by cancer type; xlsx curation must be internally consistent
2. **Code type overlaps:** Some HCPCS codes exist in CPT range; source table + format both needed for disambiguation
3. **Medication name variants:** RxNorm API may return brand names vs generic names inconsistently; prefer xlsx curated names as ground truth
4. **Cross-use false negatives:** SCT codes used for non-transplant immunotherapy may not be flagged in xlsx column 9 if not yet curated
5. **Pediatric contamination:** F/S/E/N labels developed for adult protocols; age filter (21+) must be enforced before classification

### Validation Checkpoints

- [ ] All medication names present in output match xlsx column C (no RxNorm API drift)
- [ ] Code type "UNKNOWN" count is zero (all codes deterministically classified)
- [ ] False-positive SCT codes (5 total) do not appear in any treatment episode output
- [ ] Questionable immunotherapy flags (10 codes) appear in flagged_codes summary table
- [ ] SCT cross-use flags match xlsx column 9 exactly (no dropped or added flags)
- [ ] Treatment line classification applied only to adults 21+ (pediatric cases excluded or flagged)

## Gaps and Open Questions

1. **F/S/E/N definition standardization:** Is there a NCCN/ASCO published standard for these abbreviations, or are they local conventions?
   - **Research finding:** NCCN and ASCO use "line of therapy" framework but standard abbreviations not found in search
   - **Resolution:** Trust xlsx curation; document abbreviation key in output

2. **CAR-T as immunotherapy vs cellular therapy:** Two CAR-T codes flagged as "classification TBD"
   - **Research finding:** CAR-T is a form of cellular/adoptive immunotherapy (distinct from checkpoint inhibitors)
   - **Resolution:** Flag for review; likely belongs in separate treatment category, not traditional immunotherapy

3. **Vitamin combination codes:** Why are 8 vitamin codes in immunotherapy list?
   - **Research finding:** Vitamins (D, E, C) can modulate immunotherapy efficacy but are not immunotherapy drugs themselves
   - **Resolution:** Flag as questionable; likely data entry errors or supportive care codes misclassified

4. **Multi-line episodes:** What to do when F and S codes appear in same 28-day cycle?
   - **Out of scope for v2.3:** Multi-line therapy sequencing deferred (PROJECT.md line 96)
   - **Resolution:** Apply dominant line classification (most codes) or flag as "mixed" for manual review

5. **Source table ambiguity:** Can same code appear in multiple source tables (e.g., PRESCRIBING + DISPENSING)?
   - **Research finding:** Yes, overlap detected in Phase 33 (AV+TH analysis)
   - **Resolution:** Concatenate source tables ("PRESCRIBING|DISPENSING") or prefer PRESCRIBING as primary

## Expected Gantt CSV Schema Changes

### Existing v2 Gantt Schema (16 columns)
```
patient_id, treatment_type, episode_start, episode_end, duration_days,
episode_number, triggering_codes, encounter_ids, drug_names, cancer_category,
is_hodgkin, regimen_label, is_first_line, drug_group, cause_of_death,
death_date
```

### Proposed v3 Gantt Schema (22 columns = +6 new)
```
patient_id, treatment_type, episode_start, episode_end, duration_days,
episode_number, triggering_codes, medication_names, code_type, source_table,
treatment_line, sct_cross_use_flag, questionable_immunotherapy_flag,
encounter_ids, cancer_category, is_hodgkin, regimen_label, is_first_line,
drug_group, cause_of_death, death_date, triggering_code_descriptions
```

**New columns:**
1. `medication_names` (replaces `drug_names`; curated from xlsx column C)
2. `code_type` (RXNORM/CPT/HCPCS/ICD-10-CM; deterministic from source table + format)
3. `source_table` (PRESCRIBING/PROCEDURES/DIAGNOSIS; already tracked, now surfaced)
4. `treatment_line` (F/S/E/N; extends `is_first_line` with categorical labels)
5. `sct_cross_use_flag` (TRUE/FALSE; from xlsx column 9; SCT codes used for conditioning/immunotherapy)
6. `questionable_immunotherapy_flag` (TRUE/FALSE; 10-code flagging list for manual review)
7. `triggering_code_descriptions` (human-readable; already in v2.1 outputs, formalized here)

**Backward compatibility:**
- `drug_names` → `medication_names` (column rename with improved data source)
- `is_first_line` remains (Boolean for ABVD/BV+AVD/Nivo+AVD detection)
- `treatment_line` adds categorical detail (F/S/E/N) extending Boolean `is_first_line`

## Sources

### Treatment Line Classification
- [Explanation of First-line and Second-line Chemotherapy Regimens – Callaix](https://callaix.com/firstline)
- [First-Line vs. Second-Line Therapy in Lung Cancer](https://www.patientpower.info/lung-cancer/first-line-vs-second-line-therapy-in-lung-cancer)
- [First-Line Chemotherapy - an overview | ScienceDirect Topics](https://www.sciencedirect.com/topics/medicine-and-dentistry/first-line-chemotherapy)
- [Definition of lines of treatment in metastatic colorectal cancer: a Delphi consensus](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12855278/)

### Medication Name Enrichment
- [Enhancing adverse drug reaction data quality in Canada: A high-precision pipeline for medication name standardization and enrichment](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12463261/)
- [GitHub - niazch/canada-vigilance-med-norm](https://github.com/niazch/canada-vigilance-med-norm)
- [RxNorm API for drug name normalization workflow](https://www.researchgate.net/figure/RxNorm-API-for-drug-name-normalization-workflow_fig1_377587583)

### PCORnet Code Systems
- [Exploration of PCORnet Data Resources for Assessing Use of Molecular-Guided Cancer Treatment | JCO Clinical Cancer Informatics](https://ascopubs.org/doi/10.1200/CCI.19.00142)
- [PCORnet® Common Data Model](https://pcornet.org/data/common-data-model/)
- [PCORnet® Common Data Model (CDM) Specification, Version 7.0](https://pcornet.org/wp-content/uploads/2025/05/PCORnet_Common_Data_Model_v70_2025_05_01.pdf)

### Stem Cell Transplant Coding
- [ICD-10 Code for Complications of stem cell transplant- T86.5](https://coder.aapc.com/icd-10-codes/T86.5)
- [ICD-10-CM Diagnosis Code Z94.84: Stem cells transplant status](https://www.icd10data.com/ICD10CM/Codes/Z00-Z99/Z77-Z99/Z94-/Z94.84)
- [Stem Cell Transplant - ICD-10 Documentation Guidelines](https://icdcodes.ai/diagnosis/stem-cell-transplant/documentation)

### Cancer Treatment Data Quality
- [Quality of Cancer-Related Clinical Coding in Primary Care in North Central London](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12824575/)
- [Validation of Real-World Data-based Endpoint Measures of Cancer Treatment Outcomes](https://pmc.ncbi.nlm.nih.gov/articles/PMC8861715/)
- [Quality control on digital cancer registration](https://pmc.ncbi.nlm.nih.gov/articles/PMC9778557/)

### CAR-T and Immunotherapy Classification
- [CAR T- cell therapy: A promising novel approach for treatment of cancer](https://www.sciencedirect.com/science/article/pii/S2468294226000365)
- [Engineering Immunity: Current Progress and Future Directions of CAR-T Cell Therapy](https://www.mdpi.com/1422-0067/27/2/909)
- [Editorial: Current trends in immunotherapy: from monoclonal antibodies to CAR-T cells](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12171432/)

### Oncology Timeline Annotation
- [OCTANE: Oncology Clinical Trial Annotation Engine | JCO Clinical Cancer Informatics](https://ascopubs.org/doi/10.1200/CCI.18.00145)
- [CACER: Clinical Concept Annotations for Cancer Events and Relations](https://arxiv.org/html/2409.03905v1)
- [The evolution of an integrated timeline for oncology patient healthcare](https://pmc.ncbi.nlm.nih.gov/articles/PMC2232288/)
- [UW-BioNLP at ChemoTimelines 2025](https://arxiv.org/pdf/2512.04518)

### Hodgkin Lymphoma Treatment
- [Hodgkin Lymphoma Treatment (PDQ®) - NCI](https://www.cancer.gov/types/lymphoma/hp/adult-hodgkin-treatment-pdq)
- [Impact of Time-to-Treatment Initiation and First Inter-Cycle Delay in Patients with Hodgkin Lymphoma](https://pmc.ncbi.nlm.nih.gov/articles/PMC12194712/)
