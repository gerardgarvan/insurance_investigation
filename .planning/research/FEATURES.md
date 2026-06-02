# Feature Landscape

**Domain:** PCORnet cancer registry cohort analysis — clinical data refinements
**Researched:** 2026-06-02

## Table Stakes

Features users expect in cancer registry cohort analyses. Missing = incomplete clinical validity.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Temporal separation for multiple primary cancers | SEER and IARC standards require clear temporal thresholds to distinguish synchronous from metachronous cancers | Medium | Multiple standards exist: SEER 2-month, Warren/Gates 6-month, 60-day exclusion. 7-day threshold is **more stringent** than typical standards but appropriate for encounter-level data quality. **Already implemented for HL**, extension to all cancer categories is straightforward. |
| NLPHL separate classification | C81.0 is biologically and clinically distinct from other Hodgkin Lymphomas — different treatment, better prognosis | Low | ICD-10 C81.0 (ICD-9 201.4x) is already coded separately. Requires mapping table update + downstream Gantt/summary table modifications. Standard practice in lymphoma registries. |
| Treatment source validation | Tumor registry treatment data has known reliability issues (12-32% radiation, 8-29% chemo capture) vs EHR sources (95-100% accuracy) | Medium | **Critical for research validity.** Registry-only treatment substantially overestimates radiation effects on survival. Dropping tumor registry treatment and relying on EHR sources (PRESCRIBING, DISPENSING, PROCEDURES, MED_ADMIN) is best practice. |
| ICD code replacement/deprecation tracking | ICD codes change over time; "replaced by" mappings ensure historical data is interpreted correctly | Low | Standard data quality check. Verification of existing mappings (not building new ones) is low-lift. |
| Cause of death in outcomes | NAACCR standard field; vital for survival analysis and competing risks models | Low | Death cause available from vital status linkage. Integration into existing death date outputs is straightforward. **Table stakes for cancer registries.** |
| Per-episode cancer categorization | Treatment episodes must be linked to specific cancer diagnoses to avoid conflating unrelated treatments | Medium | **Already implemented at encounter level in v1.8 (Phase 61)**. Extension to include triggering code descriptions is incremental. Treatment episode = period from initiation to discontinuation (≥45-day gap standard). |

## Differentiators

Features that elevate analysis quality. Not expected, but valued by research community.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| SCT code validation investigation | 90 patients with organ transplant code (0362) in HL cohort — likely coding error or edge case requiring clinical review | Low | **Data quality audit feature.** Investigating whether patients have other SCT codes during same encounters distinguishes true transplants from coding errors. Adds research credibility. |
| Drug grouping tables from resolved codes | Systematic drug categorization from all_codes_resolved_next_tables.xlsx enables regimen-agnostic treatment pattern analysis | Medium | Beyond standard registry reporting. Enables discovery of treatment patterns outside pre-specified regimens (ABVD, BV+AVD, Nivo+AVD). Creates reusable infrastructure for future regimen expansion. |
| Per-episode triggering code descriptions | Human-readable treatment rationale (e.g., "Doxorubicin 50mg IV" vs just "J9000") improves clinical interpretability | Low-Medium | **Enhances transparency.** Especially valuable when drug names resolved via RxNorm API (already implemented in Phase 60). Template from all_codes_resolved_next_tables.xlsx provides groupings. |
| v2.0 quality standards enforcement | Styler formatting, lintr compliance, checkmate assertions, smoke test coverage for all new/modified code | Medium | **Maintenance differentiator.** Most registry pipelines lack systematic code quality infrastructure. Ensures long-term maintainability and onboarding ease. |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Rebuilding tumor registry treatment data | Known to be incomplete (8-32% capture) and introduces survival analysis bias | Drop tumor registry treatment data; rely on EHR sources (PRESCRIBING, DISPENSING, MED_ADMIN, PROCEDURES) which achieve 95-100% accuracy |
| Multiple temporal thresholds | 2-month SEER standard, 6-month Warren/Gates, 60-day exclusion — supporting multiple standards adds complexity without clinical benefit for this cohort | Use single 7-day threshold across all cancer categories for consistency with HL implementation |
| Manual code mapping maintenance | "Replaced by" codes change with ICD updates; manual tracking is error-prone | **Verify existing mappings** from all_codes_resolved_next_tables.xlsx (one-time check), don't build automated update system (out of scope for exploratory pipeline) |
| Retrospective SCT code correction | If 0362 patients are true transplants, don't retroactively change codes | **Investigate and document** findings; flag for clinical team if systematic miscoding found, but preserve source data fidelity |
| Publication-ready Gantt visualizations | V2.1 is data refinement milestone, not visualization milestone | Produce enhanced CSV exports (Gantt v3 with new columns); defer publication-quality rendering to future milestone (VIZ-01/VIZ-02 backlog) |

## Feature Dependencies

```
Temporal separation (all cancers)
  → Depends on: Existing 7-day HL logic (Phase 51)
  → Enables: Accurate pre/post HL cancer counts (total = 6,347)

NLPHL breakout
  → Depends on: C81.0 / 201.4x code identification (existing)
  → Affects: Cancer summary tables, Gantt outputs, frequency tables
  → No blocking dependencies

SCT code investigation
  → Depends on: Procedure code cross-reference (all_codes_resolved_next_tables.xlsx)
  → Outputs: Audit findings (low/no impact on pipeline if no changes needed)

Drop tumor registry treatment
  → Depends on: EHR treatment sources already implemented (Phases 9, 60, 61)
  → Affects: Treatment episode counts (likely decrease), regimen detection (likely improve specificity)
  → Prerequisite for: Reliable treatment outcome analysis

Verify "replaced by" codes
  → Depends on: all_codes_resolved_next_tables.xlsx
  → Outputs: Validation report (low impact unless errors found)

Drug grouping tables
  → Depends on: all_codes_resolved_next_tables.xlsx groupings
  → Enables: Per-episode triggering code descriptions
  → Creates: 2 new summary tables (template-driven)

Cause of death integration
  → Depends on: Death date validation (Phase 59, Phase 62)
  → Affects: Death analysis outputs (R/65_death_date_analysis.R)
  → No blocking dependencies

Per-episode cancer category + triggering codes
  → Depends on: Encounter-level cancer linkage (Phase 61), drug grouping tables
  → Affects: Treatment episode outputs, Gantt v3 schema
  → Enables: Clinically interpretable treatment timelines
```

## MVP Recommendation

Prioritize (in order):

1. **Drop tumor registry treatment data** — Critical for research validity; affects all downstream treatment analyses. Do this FIRST before other treatment-related features.

2. **NLPHL breakout** — Low complexity, high clinical value. C81.0 is biologically distinct; separation is standard practice.

3. **Fix temporal separation for all cancer categories** — Extends existing HL logic (7-day gap) to all categories. Total population = 6,347. Required for accurate cancer summary tables.

4. **Cause of death integration** — NAACCR standard field, low complexity, enables competing risks analysis later.

5. **Per-episode cancer category + triggering codes** — Builds on existing encounter-level linkage (Phase 61); adds human-readable descriptions from drug groupings.

6. **Verify "replaced by" codes** — Data quality check; low effort, guards against historical code mapping errors.

7. **SCT code 0362 investigation** — Audit feature; non-blocking; addresses data quality question from domain expert.

8. **Drug grouping tables** — Enables regimen-agnostic treatment pattern analysis; creates reusable infrastructure.

Defer to v2.2+:
- **Waterfall chart (VIZ-01)** — Attrition logging infrastructure exists; visualization is separate effort
- **Payer-stratified Sankey (VIZ-02)** — Requires ggalluvial integration; separate visualization milestone
- **HIPAA suppression (VIZ-03)** — Apply when outputs move from exploratory to publication phase

## Implementation Notes

### Temporal Separation (All Categories)

**Existing implementation:** R/51_cancer_site_confirmation.R applies 7-day separation for HL only.

**Extension strategy:**
- Remove HL-specific filter
- Apply same `min_days_apart = 7` logic to all CANCER_CATEGORY values
- Verify total population = 6,347 (current cohort size)
- Update R/58_cancer_summary_table_pre_post.R to use revised output

**Clinical rationale:** 7 days distinguishes genuine separate primaries from administrative duplicates (same cancer coded on multiple nearby encounter dates). More stringent than SEER 60-day standard, but appropriate for encounter-level EHR data where administrative duplicates are common.

### NLPHL Breakout

**ICD codes:**
- ICD-10: C81.0 (all subcodes: C81.00, C81.01, C81.02, etc.)
- ICD-9: 201.4x (201.40, 201.41, etc.)

**Affected components:**
- Cancer category mappings (centralized in R/00_config.R or equivalent)
- Cancer summary tables (R/53_cancer_summary.R, R/58_cancer_summary_table_pre_post.R)
- Gantt outputs (R/63_gantt_encounter_level_v2.R)
- Frequency tables (any script grouping by cancer category)

**Clinical note:** NLPHL has 5-year survival >90% vs classical HL 85-90%, often treated with observation or RT alone (not chemotherapy). Separate classification enables treatment pattern comparisons.

### Drop Tumor Registry Treatment

**Sources to remove:**
- TUMOR_REGISTRY1/2/3 tables: DX_TREATMENT_STARTED_DAYS, TUMOR_RX_SUMMARY_* fields
- Any treatment episodes flagged as `source == "Tumor_Registry"` or similar

**Retain sources (EHR-based):**
- PRESCRIBING (drug orders)
- DISPENSING (dispensed medications)
- MED_ADMIN (administered medications)
- PROCEDURES (procedure codes, revenue codes)
- ENCOUNTER (DRG codes)

**Impact:** Expected decrease in treatment episode counts (registry captures 8-32% of treatments, often incomplete). Expected increase in specificity (removes spurious/duplicate entries). Required for unbiased survival analysis.

**Scripts affected:**
- R/23_treatment_episodes.R (or wherever treatment episode detection occurs)
- All downstream regimen detection scripts
- Gantt outputs

### SCT Code 0362 Investigation

**Question:** Do 90 patients with code 0362 (organ transplant) have OTHER SCT codes during those encounters?

**Approach:**
- Filter to PATID with code 0362
- For those patients, examine all procedure codes on same ENCOUNTERID
- Check for standard SCT CPT codes: 38240, 38241, 38204-38208, 38230
- Output: Crosstab of 0362 + other SCT codes; findings summary

**Expected outcome:** Either (a) 0362 is legitimate organ transplant (different from hematopoietic SCT) or (b) 0362 is coding error/placeholder. Document findings; flag for clinical team if systematic issue.

### Cause of Death

**Source:** Vital status linkage (already used for death dates in Phase 59, 62)

**Integration points:**
- R/65_death_date_analysis.R (existing death analysis script)
- Any outputs with death dates (Gantt v3, survival tables)

**NAACCR field:** Typically ICD-10 code for underlying cause of death

**Output format:** Add `cause_of_death` column to death analysis tables; group by cancer-related vs non-cancer-related for high-level summaries.

### Drug Grouping Tables

**Source:** all_codes_resolved_next_tables.xlsx — contains drug groupings from existing code resolution work

**Deliverable:** 2 new summary tables using template + groupings from xlsx

**Approach:**
- Read groupings from all_codes_resolved_next_tables.xlsx
- Create lookup table (drug code → category/description)
- Apply to treatment episodes for categorization
- Generate 2 summary tables (format TBD based on template in xlsx)

**Enables:** Per-episode triggering code descriptions (next feature)

### Per-Episode Cancer Category + Triggering Code

**Already exists (Phase 61):** Encounter-level cancer linkage — episodes have `cancer_category` field

**New addition:** Human-readable triggering code description

**Source:** Drug groupings from all_codes_resolved_next_tables.xlsx (previous feature)

**Output schema:**
```
treatment_episodes.rds:
  - episode_id
  - cancer_category (existing, from encounter linkage)
  - triggering_code (existing, raw code)
  - triggering_code_description (NEW, from drug groupings)
  - drug_name (existing, from RxNorm API Phase 60)
```

**Clinical value:** "Doxorubicin 50mg IV push (J9000)" vs "J9000" — improves Gantt chart interpretability, enables non-technical stakeholder review.

## Complexity Assessment

| Feature | Complexity | Estimated Effort | Risk |
|---------|------------|------------------|------|
| Drop tumor registry treatment | Medium | 2-4 hours | Low (removal is safer than addition; validate episode counts) |
| NLPHL breakout | Low | 2-3 hours | Low (code mapping + downstream table updates) |
| Temporal separation (all categories) | Low | 1-2 hours | Very Low (logic already exists, just remove HL filter) |
| Cause of death | Low | 1-2 hours | Low (data already linked, add column to outputs) |
| Per-episode triggering code descriptions | Low-Medium | 3-5 hours | Low (lookup table + join, depends on drug grouping tables) |
| Verify "replaced by" codes | Low | 1-2 hours | Very Low (read xlsx, compare to existing mappings, document findings) |
| SCT code investigation | Low | 1-2 hours | Very Low (exploratory query, no pipeline changes) |
| Drug grouping tables | Medium | 3-6 hours | Medium (xlsx parsing, template interpretation, 2 new outputs) |
| v2.0 quality standards | Medium | +50% per script | Low (mechanical application of styler, lintr, checkmate) |

**Total estimated effort:** 14-26 hours for core features + quality standards overhead

## Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Temporal separation standards | HIGH | Multiple authoritative sources (SEER, IARC, Warren/Gates); 7-day threshold more stringent than typical but clinically defensible |
| NLPHL classification | HIGH | ICD-10 official codes, clinical literature confirms distinct biology/treatment |
| Treatment source reliability | HIGH | Multiple studies (PMC3651576, PMC11178108, PMC12303076) document tumor registry incompleteness (8-32% capture) vs EHR 95-100% |
| ICD code replacement | MEDIUM | Standard practice documented, but specific all_codes_resolved_next_tables.xlsx mappings not verified against official ICD crosswalks |
| Cause of death | HIGH | NAACCR standard field, widely implemented in cancer registries |
| Per-episode cancer categorization | HIGH | Treatment episode definition (≥45-day gap) documented in multiple sources; encounter-level linkage is best practice |
| SCT code 0362 | LOW | Code "0362" not found in standard CPT databases; likely local/proprietary code requiring internal documentation review |
| Drug grouping complexity | MEDIUM | Template and groupings exist in all_codes_resolved_next_tables.xlsx (trusted source per project context), but specific implementation details not verified |

## Gaps to Address

1. **SCT code 0362 provenance:** Standard CPT databases (38204-38241) don't include "0362". Likely internal code or data entry artifact. Requires project-specific code documentation or data dictionary review.

2. **all_codes_resolved_next_tables.xlsx schema:** Drug grouping tables and template structure not verified. Will need to read xlsx during implementation to confirm groupings format and template requirements.

3. **Cause of death field name/format:** Vital status linkage provides death dates (confirmed in Phase 59, 62), but cause-of-death field name and coding system (ICD-10, free text, etc.) not verified. Check PCORnet CDM DEATH table or vital status source during implementation.

4. **Drug grouping table purpose:** "2 new tables" referenced but specific research questions those tables answer not documented. Clarify purpose with domain expert before implementation to ensure correct structure.

5. **Total population = 6,347 validation:** Current cohort size referenced as validation target for temporal separation fix. Confirm this is correct baseline before implementing changes.

## Sources

**PCORnet & Cancer Registry Integration:**
- [Implementing Cancer Registry Data with the PCORnet Common Data Model](https://pmc.ncbi.nlm.nih.gov/articles/PMC11658786/) — HIGH confidence, 2024 publication documenting 11-site implementation with 572,902 tumors
- [Exploration of PCORnet Data Resources for Molecular-Guided Cancer Treatment](https://pmc.ncbi.nlm.nih.gov/articles/PMC7469597/) — HIGH confidence, documents CPT/HCPCS/RxNorm coding for treatment identification

**NLPHL Classification:**
- [ICD-10-CM C81.0 Nodular Lymphocyte Predominant Hodgkin Lymphoma](https://www.icd10data.com/ICD10CM/Codes/C00-D49/C81-C96/C81-/C81.0) — HIGH confidence, official ICD-10 2026 codes
- [Characterization of NLPHL Microenvironment](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5187927/) — MEDIUM confidence, clinical background on NLPHL as distinct entity

**Treatment Data Reliability:**
- [New Accountability, New Challenges: Improving Treatment Reporting to a Tumor Registry](https://pmc.ncbi.nlm.nih.gov/articles/PMC3651576/) — HIGH confidence, documents 12-32% radiation, 8-29% chemo capture in tumor registries
- [Cancer Registry Enrichment via EHR Linkage](https://pmc.ncbi.nlm.nih.gov/articles/PMC11178108/) — HIGH confidence, only 5% surgery, 1% radiation, 7% chemo updates from EHR
- [Real-time Data in Cancer Registries: Automated System Validation](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12303076/) — HIGH confidence, automated EHR extraction achieves 100% diagnosis accuracy, 95%+ treatment accuracy
- [Impact of Adjuvant Radiation Analysis Using Registry Data](https://pubmed.ncbi.nlm.nih.gov/17899285/) — HIGH confidence, survival analysis without chemo data overestimates radiation benefit

**Multiple Primary Cancer Definitions:**
- [Second Primary Cancer Risk - Impact of Different Definitions](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4005906/) — HIGH confidence, compares SEER vs IACR/IARC rules
- [Multiple Primary Tumours: Challenges and Approaches](https://pmc.ncbi.nlm.nih.gov/articles/PMC5519797/) — MEDIUM confidence, documents 2-month SEER, 6-month Warren/Gates, 60-day exclusion thresholds

**Cause of Death:**
- [Cancer Statistics 2026](https://pmc.ncbi.nlm.nih.gov/articles/PMC12798275/) — HIGH confidence, NAACCR standards for death reporting
- [Accuracy of Cause of Death in Cancer Registry](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3879655/) — MEDIUM confidence, validation of registry cause-of-death data

**Treatment Episodes:**
- [Assessment of Costs with Adverse Events](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5898735/) — MEDIUM confidence, treatment episode = initiation to discontinuation (≥45-day gap)

**Cancer Registry Data Quality:**
- [National Cancer Database Standardized Framework](https://pmc.ncbi.nlm.nih.gov/articles/PMC11300494/) — HIGH confidence, documents completeness, comparability, timeliness, validity framework
- [Quality Assessment of Pathologic Data in Cancer Registry](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9348200/) — MEDIUM confidence, ICD-O-3 coding quality importance

**Stem Cell Transplant Codes:**
- [CPT Codes 38240, 38241, 38204-38208, 38230](https://www.aapc.com/codes/cpt-codes/) — MEDIUM confidence, standard SCT CPT codes (but 0362 not found)
