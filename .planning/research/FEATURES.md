# Feature Landscape

**Domain:** Cancer epidemiology cohort refinement and clinical timeline visualization (Hodgkin Lymphoma study)
**Researched:** 2026-05-22

## Table Stakes

Features expected in any cancer cohort study with temporal analysis. Missing these = protocol violations or results not credible.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Exclude benign/uncertain D-codes from cancer classification | ICD-10 Chapter 2 separates malignant (C00-D49) from benign (D10-D36), in situ (D00-D09), and uncertain behavior (D37-D48) neoplasms. Cancer registries and epidemiology studies analyze only malignant neoplasms. | Low | D00-D48 codes must be filtered out. Existing PREFIX_MAP already has ICD code prefix logic — just add filter predicate before cancer summary generation. |
| Cohort confirmation with multiple diagnosis dates | Single-code diagnoses may be rule-out, provisional, or billing artifacts. Epidemiology standards require temporal validation (2+ codes 7+ days apart) to confirm persistent diagnosis. | Medium | Requires diagnosis date parsing, grouping by PATID+code prefix, temporal gap calculation. Existing 2-date (R/50) and 7-day separation (R/51) scripts provide foundation — apply to HL cohort filter. |
| Temporal filtering relative to index cancer diagnosis | Secondary cancer analysis requires reference to index cancer date. SEER methodology defines index cancer as first SEER-recorded cancer; at-risk period for subsequent cancers starts at index diagnosis date. | Medium | Requires identifying first HL diagnosis date per patient, then filtering DIAGNOSIS table to DX_DATE > first_hl_date. Existing date parsing + attrition logging infrastructure supports this. |
| Death date as clinical endpoint | PCORnet CDM includes DEATH_DATE in DEMOGRAPHIC. Death is a standard clinical endpoint for cancer timeline visualizations and survival analysis. Missing death dates = incomplete follow-up. | Low | DEMOGRAPHIC table accessible via DuckDB with DEATH_DATE column. Add to Gantt as final event (treatment type = "Death"). Existing Gantt CSV export (gantt_episodes.csv, gantt_detail.csv) supports adding new treatment types. |
| Cancer site category labeling | Clinical interpretation of treatment episodes requires knowing what cancer is being treated. Standard practice maps ICD codes to human-readable cancer site categories (e.g., SEER site recode, ICD-O-3 groupings). | Low | CancerSiteCategories.xlsx already provides 42-category mapping via ICD code ranges. PREFIX_MAP in R/00_config.R implements prefix → category lookup. Add category column to gantt_episodes.csv via PREFIX_MAP join. |

## Differentiators

Features that enhance analysis quality beyond minimum standards. Not required, but add significant value.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Hodgkin-specific binary flag in Gantt data | Enables quick visual filtering in Gantt charts (e.g., color-code HL vs non-HL treatments). Supports exploratory question: "Do patients receive HL-specific treatments after non-HL cancer diagnosis?" | Low | Derived from cancer category label. If category = "Hodgkin Lymphoma" → is_hodgkin = TRUE, else FALSE. Zero computation cost once category label exists. |
| Temporal filtering with comparison outputs | Producing both filtered (cancers after HL) and unfiltered cancer summary tables enables validation of filtering logic and comparison of cancer burden before vs after HL diagnosis. | Low | Clone cancer_summary_table.xlsx generation with filtered DIAGNOSIS input. Minimal code duplication (wrap in function). Provides quality assurance for temporal filtering. |
| 90-day gap episode aggregation (already implemented) | Treatment episodes with <90 day gaps represent continuous treatment for the same condition. Oncology claims analysis standard is 90-180 day gap bridging. This pipeline uses 90 days. | N/A | Already implemented in v1.6 treatment episode system. Referenced here because it informs Gantt bar structure — each bar = one 90-day-gapped episode. |
| Date-based cancer confirmation metrics (already implemented) | 2+ distinct dates and 7-day gap are stronger confirmation signals than simple code frequency. Reduces false positives from rule-out diagnoses. | N/A | Already implemented in R/50 (2-date) and R/51 (7-day separation). Cancer summary table includes these metrics (columns for confirmation status). Applied to cohort filter in this milestone. |
| Human-readable code descriptions in Gantt (already implemented) | ICD/CPT/NDC codes are not interpretable without lookup. Gantt CSV includes code descriptions (already shipped v1.6 Phase 49). | N/A | Already implemented. gantt_detail.csv includes CODE_DESCRIPTION. Enables clinical review without cross-referencing codebooks. |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Automatic removal of D-codes from existing xlsx outputs retroactively | Breaks reproducibility — outputs already generated with D-codes (v1.6) are snapshots of that analysis version. | Generate new versions with "_no_benign" suffix for clarity. Preserve existing outputs for version comparison. |
| Death date imputation or estimation | PCORnet DEATH_DATE is already populated (from SSA Death Master File + Obituary.com per PCORnet infrastructure). Imputation introduces bias and is not standard practice. | Use DEATH_DATE as-is. If missing, patient is censored (standard survival analysis approach). Do not fill NAs. |
| Chemotherapy-specific treatment classification in Gantt | Treatment type taxonomy already exists (7 types: chemo, surgery, radiation, transplant, immunotherapy, targeted, hormone). Adding finer granularity (e.g., ABVD vs BEACOPP) requires morphology codes (ICD-O-3) not reliably in PCORnet CDM. | Use existing treatment types. Cancer category label + treatment type provides sufficient granularity for insurance disparity analysis. |
| Global minimum gap enforcement for cancer confirmation | Not all cancers need 2+ codes 7 days apart (e.g., single pathology-confirmed diagnosis from TR). This requirement is specific to HL cohort confirmation in this study, not a universal data quality rule. | Apply 2-date + 7-day logic ONLY to HL cohort filter predicate. Do not apply globally to all cancer codes in cancer summary table. |
| Filtering D-codes from Gantt chart | Gantt visualizes treatment episodes, not diagnosis codes. D-codes (if present) appear in DIAGNOSIS table but don't trigger treatment episodes (treatment detection uses C-codes, procedures, prescriptions). Filtering D-codes from Gantt would have no effect. | Only filter D-codes from cancer summary table (which is diagnosis-focused). Leave Gantt logic unchanged. |
| Subsequent cancer definition based on different primary site | SEER defines subsequent primary cancers (SPCs) using complex rules (same site = recurrence unless >5 years apart, different histology, etc.). This study is exploratory — "cancer after HL diagnosis date" is sufficient temporal filter. | Use simple temporal filter (DX_DATE > first_hl_date). Do not attempt to classify recurrence vs new primary. Out of scope for insurance disparity analysis. |

## Feature Dependencies

```
Exclude D-codes from cancer summary
  └─> Requires PREFIX_MAP (already exists in R/00_config.R)

HL cohort confirmation (2+ codes, 7 days apart)
  └─> Requires R/50 2-date logic
  └─> Requires R/51 7-day separation logic
  └─> Applied as named predicate filter (has_confirmed_hl or similar)

Temporal filtering (cancers after first HL diagnosis)
  └─> Requires HL cohort confirmation (to get valid first HL date)
  └─> Requires DIAGNOSIS table with DX_DATE
  └─> Produces filtered cancer_summary_table variant

Cancer category label in Gantt
  └─> Requires PREFIX_MAP (already exists)
  └─> Requires gantt_episodes.csv structure (already exists)
  └─> Adds CANCER_CATEGORY column

is_hodgkin flag in Gantt
  └─> Requires cancer category label
  └─> Derived: CANCER_CATEGORY == "Hodgkin Lymphoma" → TRUE

Death date in Gantt
  └─> Requires DEMOGRAPHIC.DEATH_DATE (already accessible via DuckDB)
  └─> Treats death as treatment type for visualization
  └─> Adds to gantt_episodes.csv as final bar (if DEATH_DATE exists)
```

## MVP Recommendation

Prioritize table stakes in this order:

1. **Exclude D-codes from cancer summary** — Clinical validity issue. D10-D48 codes are not malignant cancers and should never appear in cancer incidence/summary tables. Affects interpretation of all downstream results.

2. **HL cohort confirmation (2+ codes, 7+ days apart)** — Reduces false positives. Single HL code could be rule-out diagnosis. Temporal validation ensures persistent HL diagnosis. Required before temporal filtering.

3. **Cancer category label in Gantt** — Human-readability for Gantt charts. Without labels, Gantt shows ICD codes (C81.90) instead of "Hodgkin Lymphoma". Blocks clinical review.

4. **is_hodgkin flag in Gantt** — Zero-cost derivation once category label exists. Enables quick visual filtering.

5. **Death date in Gantt** — Completes clinical timeline. Shows whether patient died during follow-up, essential for survivorship analysis.

6. **Temporal filtering relative to first HL diagnosis** — Research question: "What other cancers occur after HL?" Deferred to after cohort confirmation because requires valid first HL date.

**Defer:**
- Comparison outputs (filtered vs unfiltered cancer summary) — Validation/QA feature, not blocking. Add after filtered version works.

**Rationale for ordering:**
- D-code exclusion first: affects all cancer classification downstream
- HL cohort confirmation second: reduces false positives before temporal filtering
- Gantt enhancements (category, is_hodgkin, death) third: independent of temporal filtering, unblocks clinical review
- Temporal filtering last: depends on confirmed HL cohort, addresses specific research question

## Implementation Complexity Assessment

| Feature | LOC Estimate | Risk | Dependencies |
|---------|--------------|------|--------------|
| Exclude D-codes | ~10 | Low | Filter predicate in cancer summary generation. PREFIX_MAP already handles code prefixes. Add `!str_starts_with(dx, "D")` before summary aggregation. |
| HL cohort confirmation | ~50 | Medium | Adapt R/50 + R/51 logic to named predicate. Group DIAGNOSIS by PATID, filter to C81.*, count distinct DX_DATEs, calculate min date gap. Risk: date parsing edge cases (already handled in existing scripts). |
| Cancer category label | ~20 | Low | Join gantt_episodes with PREFIX_MAP. Map ICD prefix → category. Existing PREFIX_MAP tested via cancer summary table (v1.6 Phase 54). |
| is_hodgkin flag | ~5 | Low | Derived column: `is_hodgkin = (CANCER_CATEGORY == "Hodgkin Lymphoma")`. No external dependencies. |
| Death date in Gantt | ~30 | Medium | Query DEMOGRAPHIC.DEATH_DATE, join to cohort, add as treatment type. Risk: DEATH_DATE may have 1900 sentinels (already filtered in v1.1 Phase 17). Need to handle NAs (no death recorded). |
| Temporal filtering | ~40 | Medium | Identify first HL diagnosis date per patient (from confirmed HL cohort), filter DIAGNOSIS to DX_DATE > first_hl_date, regenerate cancer summary table. Risk: Patients with no post-HL cancers = empty result (expected). |

**Total estimated LOC for all features: ~155 lines** (excluding comments/logging)

**Critical path:** HL cohort confirmation blocks temporal filtering. All other features are independent.

## Edge Cases and Validation

### D-Code Exclusion
- **Edge case:** What if a patient has only D-codes (no C-codes)?
  - **Expected behavior:** Excluded from cancer summary table (no malignant cancers).
  - **Validation:** Count patients before/after D-code filter. Log attrition.

### HL Cohort Confirmation
- **Edge case:** Patient has 5 HL codes all on the same date.
  - **Expected behavior:** Fails 7-day separation rule. Excluded from confirmed HL cohort.
  - **Validation:** Check distinct date count, not total code count.

- **Edge case:** Patient has 2 HL codes 6 days apart.
  - **Expected behavior:** Fails 7-day rule (need ≥7 days). Excluded.
  - **Validation:** Use `>=7` not `>6` in gap calculation.

- **Edge case:** Patient has C81.90 and C81.01 (different subtypes) 10 days apart.
  - **Expected behavior:** Passes confirmation. Both are C81.* (Hodgkin Lymphoma).
  - **Validation:** Prefix match (C81.*), not exact code match.

### Temporal Filtering
- **Edge case:** First HL diagnosis is the only cancer code in record.
  - **Expected behavior:** Filtered cancer summary table is empty for this patient (no post-HL cancers).
  - **Validation:** Patients with no post-HL cancers should not appear in filtered output.

- **Edge case:** Patient has non-HL cancer diagnosed same day as first HL diagnosis.
  - **Expected behavior:** DX_DATE > first_hl_date excludes same-day diagnoses. Only strictly after.
  - **Validation:** Use `>` not `>=` for temporal filter.

- **Edge case:** Patient has HL relapse (new HL code after first HL).
  - **Expected behavior:** Included in filtered cancer summary (HL after HL is still "post-HL cancer").
  - **Validation:** Do not exclude C81.* codes from post-HL filter.

### Cancer Category Label
- **Edge case:** ICD code not in PREFIX_MAP (e.g., rare code).
  - **Expected behavior:** Category = NA or "Other/Unknown".
  - **Validation:** Left join to PREFIX_MAP. Handle NAs gracefully. Log unmapped codes.

- **Edge case:** Overlapping ICD ranges in CancerSiteCategories.xlsx.
  - **Expected behavior:** PREFIX_MAP uses first match (already handled in config).
  - **Validation:** Verify PREFIX_MAP construction in R/00_config.R. No duplicate prefixes.

### Death Date
- **Edge case:** DEATH_DATE = 1900-01-01 (sentinel value).
  - **Expected behavior:** Filtered out (1900 sentinel filtering already implemented in v1.1 Phase 17).
  - **Validation:** Apply existing `filter_1900_dates()` helper to DEATH_DATE.

- **Edge case:** DEATH_DATE is NA (no death recorded).
  - **Expected behavior:** No death bar in Gantt. Patient is censored.
  - **Validation:** `if (!is.na(DEATH_DATE))` before adding death treatment type.

- **Edge case:** DEATH_DATE < first treatment date (data quality issue).
  - **Expected behavior:** Include anyway (data as-is philosophy). Flag in data quality report if needed.
  - **Validation:** Do not filter. Accept that some dates may be out of sequence.

## Data Quality Considerations

| Feature | Potential Data Issue | Mitigation |
|---------|---------------------|------------|
| D-code exclusion | D-codes may be coded alongside C-codes (e.g., D05 carcinoma in situ + C50 breast cancer for same patient) | Expected. Filter D-codes at summary level, not patient level. Patient can have both D and C codes. |
| HL cohort confirmation | Missing DX_DATEs for some codes | Filter to !is.na(DX_DATE) before temporal gap calculation. Log attrition ("X patients excluded: no DX_DATE"). |
| Temporal filtering | First HL date may predate OneFlorida enrollment | Expected (prior diagnosis). Use earliest DX_DATE in available data. Do not impute. |
| Cancer category | PREFIX_MAP may not cover all ICD codes in data | Log unmapped codes. Review frequency. Add to PREFIX_MAP if common. |
| Death date | DEATH_DATE may lag true death (reporting delay) | Accept lag. PCORnet quarterly refresh means some deaths may appear months later. Do not adjust. |

## Sources

### ICD-10 Coding and Cancer Classification
- [2026 ICD-10-CM Codes C00-D49: Neoplasms](https://www.icd10data.com/ICD10CM/Codes/C00-D49)
- [ICD-10-CM Chapter 2: Neoplasms (C00-D49) | SEER Training](https://training.seer.cancer.gov/icd10cm/neoplasm/)
- [D Codes - SEER Training Modules](https://training.seer.cancer.gov/icd10cm/neoplasm/d-codes.html)
- [2026 ICD-10-CM Codes D37-D48: Neoplasms of uncertain behavior](https://www.icd10data.com/ICD10CM/Codes/C00-D49/D37-D48)
- [2026 ICD-10 Excludes1 to Excludes2 Coding Updates](https://www.allzonems.com/blogs/icd10-excludes1-excludes2-updates)

### Cohort Confirmation and Validation
- [September 2025 Acknowledgement 2 SEER Program Coding and Staging Manual 2026](https://seer.cancer.gov/manuals/2026/SPCSM_2026_MainDoc.pdf)
- [2022 revised European recommendations for the coding of the basis of diagnosis of cancer cases](https://pmc.ncbi.nlm.nih.gov/articles/PMC10755738/)
- [Real-time data in cancer registries: Validation of an automated data extraction system](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12303076/)
- [Variations in Using Diagnosis Codes for Defining Age-Related Macular Degeneration Cohorts](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11864795/)

### Secondary Malignancy and Temporal Analysis
- [Second cancer risk following Hodgkin lymphoma - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC5667959/)
- [Subsequent Primary Cancer Risk Is on the Rise in Cancer Survivors](https://www.cancertherapyadvisor.com/news/subsequent-primary-cancer-risk-survivors/)
- [Cancer statistics, 2026 - CA: A Cancer Journal for Clinicians](https://acsjournals.onlinelibrary.wiley.com/doi/10.3322/caac.70043)
- [Incidence and time trends of second primary malignancies after non-Hodgkin lymphoma](https://ashpublications.org/bloodadvances/article/6/8/2657/483555/Incidence-and-time-trends-of-second-primary)

### PCORnet CDM and Death Date
- [PCORnet v6.0](https://data-models-service.research.chop.edu/models/pcornet/6.0.0)
- [Characteristics of 24,516 Patients Diagnosed with COVID-19 in PCORnet](https://www.medrxiv.org/content/10.1101/2020.08.01.20163733.full.pdf)

### Clinical Timeline Visualization
- [Communicating cancer treatment with pictogram-based timeline visualizations - PMC](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11833489/)
- [Gantt Chart Software for Health Care Professionals](https://clickup.com/features/gantt/health-care-professionals)

### Treatment Episode Methodology
- [Real-World Treatment Patterns in Relapsed/Refractory Multiple Myeloma - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC12301936/)

### SEER Cancer Site Recoding
- [Site Recode - SEER](https://seer.cancer.gov/siterecode/)
- [Variable Definitions | U.S. Cancer Statistics | CDC](https://www.cdc.gov/united-states-cancer-statistics/public-use/variable-definitions.html)

### Hodgkin Lymphoma ICD-10 Codes
- [2026 ICD-10-CM Codes C81*: Hodgkin lymphoma](https://www.icd10data.com/ICD10CM/Codes/C00-D49/C81-C96/C81-)

## Confidence Assessment

| Source Type | Confidence | Rationale |
|-------------|------------|-----------|
| ICD-10 structure (C vs D codes) | HIGH | Official SEER training materials, ICD-10-CM 2026 code sets, CDC classification manuals |
| Cancer registry practices (D-code exclusion) | HIGH | SEER coding manual 2026, European cancer registry recommendations |
| Temporal validation (2+ codes, 7+ days) | MEDIUM | Standard practice in EHR validation studies, but 7-day threshold not universally mandated. Some studies use 30 days. Project already chose 7 days (R/51). |
| PCORnet DEATH_DATE | HIGH | PCORnet CDM v6.0 specification, published research using PCORnet mortality data |
| 90-day treatment episode gaps | HIGH | Oncology claims analysis standard, published studies use 90-180 day bridging |
| Gantt chart for clinical timelines | HIGH | Published research on cancer treatment timeline visualization |
| SEER subsequent cancer methodology | HIGH | Official SEER manuals, published cancer statistics 2026 |

**Overall confidence: HIGH** — All table stakes features are standard epidemiology/cancer registry practices with official documentation. Implementation complexity is low-medium (existing infrastructure supports all features).
