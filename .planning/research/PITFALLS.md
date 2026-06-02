# Pitfalls Research

**Domain:** Clinical Data Refinements for Cancer Cohort Analysis Pipelines
**Researched:** 2026-06-02
**Confidence:** MEDIUM

## Critical Pitfalls

### Pitfall 1: NLPHL Breakout Double-Counting or Loss

**What goes wrong:**
Breaking out NLPHL (C81.0 / 201.4x) from parent Hodgkin Lymphoma creates counting errors. Either: (1) NLPHL patients get counted in BOTH categories, inflating HL totals, or (2) NLPHL patients disappear from HL entirely, breaking continuity with prior reports and invalidating the HL cohort definition (currently requires HL diagnosis, which historically included NLPHL).

**Why it happens:**
NLPHL is a clinically distinct subtype but historically coded under Hodgkin Lymphoma. Existing code uses `C81.*` ranges to detect HL, which includes C81.0. Breaking it out requires mutually exclusive classification logic that developers often implement incorrectly as overlapping sets or forget to update all downstream dependencies on HL counts.

**How to avoid:**
1. Create NLPHL category FIRST, THEN define HL as "C81.* EXCLUDING C81.0"
2. Create validation check: `nrow(nlphl) + nrow(hl_excluding_nlphl) == nrow(original_hl_cohort)`
3. Add unit test comparing new counts to baseline: expect NLPHL + HL_classical = original HL total
4. Update CANCER_SITE_MAP in R/00_config.R with explicit exclusion logic, not just additive patterns
5. Check ALL scripts that filter for HL diagnosis — grep for "C81" patterns across codebase

**Warning signs:**
- HL cohort size changes unexpectedly after NLPHL breakout
- Total cancer diagnosis counts don't match sum of subcategories
- Encounter-level cancer linkage scripts (R/61) show HL patients with NLPHL codes but no NLPHL flag
- Gantt charts show encounters coded as both HL and NLPHL simultaneously
- Smoke test (R/88) shows HL cohort size drift without corresponding patient loss explanation

**Phase to address:**
Phase 1 (NLPHL breakout) — requires immediate validation infrastructure before any production use

---

### Pitfall 2: Tumor Registry Removal Silently Drops Treatment Episodes

**What goes wrong:**
Dropping all treatment data sourced from tumor registry causes massive undercounting of treatment episodes without visible error. Tumor registry captures initial treatment dates that PROCEDURES/PRESCRIBING may miss (especially for treatments occurring outside claims-generating encounters or at external facilities). Episode counts plummet but pipeline completes successfully, creating false narrative of reduced treatment access.

**Why it happens:**
Tumor registry treatment data has known accuracy limitations compared to claims data (47-91% agreement per literature), leading teams to drop it entirely. However, tumor registry is often the ONLY source for certain treatments (e.g., treatments at non-networked facilities, bundled procedures not itemized in claims). Removing it creates coverage gaps rather than improving accuracy. The pipeline doesn't fail because missing data ≠ invalid data in R.

**How to avoid:**
1. BEFORE dropping: quantify overlap — how many episodes are ONLY in tumor registry vs. multi-source?
2. Create "source_coverage_analysis.R" showing episode counts by source combinations (TR-only, claims-only, both)
3. If dropping TR, document expected count reduction and validate against known treatment rates
4. Alternative: flag TR-sourced episodes as "lower_confidence" rather than dropping entirely
5. Add assertion: if treatment episode count drops >20% after source removal, halt pipeline with explicit warning

**Warning signs:**
- Treatment episode counts drop >30% after tumor registry removal
- Gantt chart shows large gaps in treatment timeline that didn't exist in v1.8
- Payer analysis shows sudden shift toward payers with better claims coverage (selection bias)
- Patient counts with "no treatment detected" increase substantially
- First-line therapy detection rate drops (relies on comprehensive episode capture)

**Phase to address:**
Phase 2 (Treatment source audit) — must quantify impact before implementing removal in Phase 3

---

### Pitfall 3: 7-Day Gap Applied Retrospectively Breaks Pre/Post Counts

**What goes wrong:**
Extending 7-day gap requirement to ALL cancer categories (not just HL) retrospectively invalidates existing pre/post cancer summary tables. Total population ≠ 6,347 because previous analysis used 2-date confirmation without gap requirement. Comparing new gap-enforced results to old results creates false conclusions about cancer incidence changes. Outputs appear valid (no errors) but represent fundamentally different populations.

**Why it happens:**
Gap requirements improve specificity (reduce spurious diagnoses from data entry errors or historical codes) but decrease sensitivity. Teams apply new validation rules to existing datasets without regenerating baseline comparisons, treating "refined" as "improved version" rather than "different cohort definition." R pipelines don't enforce schema versioning, so old and new outputs coexist with identical filenames.

**How to avoid:**
1. Version output files: `cancer_summary_table_pre_post_v1.rds` vs. `cancer_summary_table_pre_post_v2_7day.rds`
2. Create comparison table showing before/after counts for each cancer category
3. Add pipeline metadata: record which validation rules were applied (gap days, date confirmation method)
4. Update reference manual (R/89) to document breaking change in cancer confirmation logic
5. Re-run ENTIRE pipeline from cohort selection forward with new rules (not just cancer summary scripts)
6. Add smoke test check: verify total population matches expected value with footnote explaining rule change

**Warning signs:**
- Total population in new outputs doesn't match expected 6,347
- Pre/post HL diagnosis counts shift unexpectedly
- Attrition logs show large drops in cancer diagnosis counts without epidemiological explanation
- Payer stratification changes (gap requirement may differentially affect data sources)
- Death date analysis shows patients dying of cancers not in refined confirmation set

**Phase to address:**
Phase 4 (7-day gap implementation) — requires full pipeline regeneration and explicit documentation

---

### Pitfall 4: SCT Code 0362 Investigation Conflates Codes and Encounters

**What goes wrong:**
Investigating "do the 90 patients with SCT code 0362 have OTHER SCT codes during THOSE encounters?" seems straightforward but trips over encounter-level vs. patient-level vs. code-level granularity. Analysis returns TRUE for patients with OTHER SCT codes anywhere in their history, not necessarily during same encounters as 0362, creating false positive overlap reports.

**Why it happens:**
R dplyr pipelines naturally work at patient-level (group_by(PATID)). Encounter-level analysis requires explicit ENCOUNTERID joins and temporal filtering. Code 0362 may appear in PROCEDURES while other SCT codes appear in PRESCRIBING/DISPENSING for same clinical event but different encounters (pre-admission vs. procedure day vs. post-discharge). "Those encounters" is clinically meaningful but programmatically ambiguous.

**How to avoid:**
1. Define scope explicitly: same ENCOUNTERID only? +/- N day window? Same treatment episode?
2. Structure analysis as: filter to 0362 encounters → inner_join on ENCOUNTERID → check for other SCT codes
3. Report stratified results: same encounter / same 7-day window / same 30-day episode / anywhere in history
4. Use encounter-level cancer linkage pattern from v1.8 Phase 61 as template
5. Validate with manual chart review of 5-10 patients to confirm programmatic definition matches clinical intent

**Warning signs:**
- Overlap percentages >90% (likely capturing patient-level, not encounter-level codes)
- Same SCT code appears as "other code" in results (self-overlap from different encounters)
- Temporal gaps between 0362 and "other codes" >30 days
- Results don't match clinical expectations (ask domain expert: should we see high overlap?)

**Phase to address:**
Phase 5 (SCT code investigation) — requires careful scoping and domain expert validation

---

### Pitfall 5: Replaced-By Code Verification Creates Circular Mappings

**What goes wrong:**
Verifying "replaced by" codes from all_codes_resolved_next_tables.xlsx without checking for circular references creates infinite loops in code resolution logic. Code A replaced by B, B replaced by C, C replaced by A. Pipeline hangs or produces nonsensical results (all codes map to empty set).

**Why it happens:**
ICD code mapping data is manually curated and maintained across multiple revisions. Circular references emerge from: (1) bidirectional synonyms incorrectly encoded as replacements, (2) version mismatches (ICD-9 to ICD-10 then back), (3) copy-paste errors in xlsx. Verification focuses on "does mapping exist?" not "is mapping graph acyclic?" R's case_when() evaluates top-to-bottom, masking cycles until full resolution is attempted.

**How to avoid:**
1. Load replacement mappings into graph structure (igraph package)
2. Check for cycles: `igraph::is_dag()` should return TRUE
3. For each code, compute transitive closure (all descendants) and verify no self-reference
4. Flag codes with replacement chains >3 steps (likely data quality issue)
5. Create validation report: code → immediate replacement → final resolution
6. Cross-reference against official CMS/WHO conversion tables where available (see SEER ICD-9 to ICD-10 mapping)

**Warning signs:**
- Infinite loops during code resolution (R session hangs)
- Codes resolve to empty string or NA after multi-step mapping
- Replacement chain length varies wildly (some 1-step, some 10-step)
- Multiple codes resolve to same endpoint creating unexpected duplicates
- Historical codes disappear entirely (mapped to invalid codes)

**Phase to address:**
Phase 6 (Replaced-by code verification) — before integration into production code

---

### Pitfall 6: External Classification File (XLSX) Creates Runtime Dependencies

**What goes wrong:**
Creating 2 new tables from all_codes_resolved_next_tables.xlsx by reading xlsx at runtime creates fragile pipeline with hidden dependencies. If xlsx file moves, gets corrupted, or columns rename, pipeline fails in production. Worse: if xlsx updates with new groupings, rerunning old scripts produces different results (non-reproducible research).

**Why it happens:**
XLSX files are convenient for domain experts (clinicians) to maintain classification logic without coding. However, runtime xlsx reads via readxl::read_excel() create mutable external dependencies. Unlike code, xlsx changes aren't version-controlled effectively (binary diffs useless), making it hard to track what changed between pipeline runs. Teams use xlsx for "configuration" without realizing it's actually "code."

**How to avoid:**
1. Follow AMC_PAYER_LOOKUP pattern from v1.5 Phase 36: centralize mappings in R/00_config.R as named lists
2. Create conversion script: read xlsx → generate R code defining classification tables → commit R code
3. Snapshot xlsx in version control alongside generated R code (date-stamped)
4. Add checkmate assertions: verify expected columns/types before processing
5. Document xlsx → R conversion in reference manual (R/89)
6. Use renv to snapshot xlsx file path and hash in lockfile metadata (if runtime read required)

**Warning signs:**
- Pipeline fails with "cannot find file" errors when run from different working directory
- Results differ between runs without code changes
- Smoke test (R/88) passes locally but fails in production
- Column name mismatches between xlsx and code expectations
- Classification categories in outputs don't match domain expert's current xlsx

**Phase to address:**
Phase 7 (New tables from xlsx) — requires dependency management strategy before implementation

---

### Pitfall 7: Cause of Death Integration Without Data Quality Validation

**What goes wrong:**
Adding cause of death to outputs without validating data quality creates misleading mortality analyses. Death dates exist for 1,295 patients but cause of death may be: (1) missing for substantial fraction, (2) miscoded (external causes vs. cancer-specific), (3) inconsistent across sources (EHR vs. registry vs. state vital stats), or (4) temporally misaligned (cause recorded before actual death). Pipeline produces tables with cause of death column but 60%+ missing/invalid values.

**Why it happens:**
Cause of death is notoriously incomplete in EHR data (relies on external linkage to state death certificates, which have 3-12 month reporting lag). Teams add `DEATH.CAUSE_OF_DEATH` column without checking completeness or validity. PCORnet CDM includes death_cause but doesn't mandate population. Recent research shows that integrating EHR with external mortality databases improves sensitivity but requires ML models for cause prediction when missing.

**How to avoid:**
1. Profile data quality FIRST: what % of deaths have cause coded? How many unique cause codes?
2. Cross-reference against existing death date validation from v1.8 Phase 59 (1,295 validated deaths)
3. Create missingness analysis stratified by payer (claims vs. EHR sites have different coverage)
4. Flag impossible causes (cause doesn't align with cancer cohort or patient history)
5. Document limitations in outputs: "Cause of death available for N (X%) of deaths"
6. Consider external linkage (NDI, state vital statistics) or predictive models (see research: ML models with 86% accuracy)
7. Add HIPAA suppression for rare causes (counts 1-10)

**Warning signs:**
- Cause of death missing for >40% of deaths
- Cause codes show administrative codes (unknown, pending) rather than clinical causes
- Cause of death includes non-cancer causes for cancer cohort (trauma, accidents) without explanation
- Temporal mismatches: cause date ≠ death date
- Payer stratification shows complete cause coverage for some payers, 0% for others (source bias)

**Phase to address:**
Phase 8 (Cause of death inclusion) — data quality profiling required before production use

---

### Pitfall 8: Per-Episode Cancer Categorization Without Temporal Boundaries

**What goes wrong:**
Assigning cancer_category per treatment episode seems straightforward but breaks when single episode spans multiple cancer diagnoses or diagnosis timing is ambiguous relative to treatment. Episode gets assigned: (1) most recent diagnosis (may not be the treated cancer), (2) first diagnosis (may be historical, not active), or (3) all diagnoses (creates multi-valued column). Gantt charts show breast cancer treatment episodes during HL diagnosis periods.

**Why it happens:**
Treatment episodes are defined by prescription/procedure dates, not diagnosis dates. Cancer diagnoses accumulate over patient lifetime. Encounter-level cancer linkage (v1.8 Phase 61) links diagnosis to encounters, but treatment episodes may span multiple encounters or have no direct encounter link (TUMOR_REGISTRY dates). "Per episode" assumes 1:1 episode:cancer mapping, but real data has 1:many and many:1 cases.

**How to avoid:**
1. Extend encounter-level linkage pattern: episode → encounters → diagnoses within episode window
2. Define temporal priority: diagnosis within +/- 30 days of episode start takes precedence
3. Handle multi-cancer episodes: flag as "multi_cancer" rather than choosing arbitrarily
4. Use drug groupings from xlsx to inform cancer category (chemo drugs indicate likely cancer type)
5. Create validation report: % episodes with 0/1/2+ cancer categories
6. Add domain expert review for ambiguous cases (multi-cancer episodes)
7. Document logic in reference manual: "Episode cancer = diagnosis within 30 days OR drug-inferred type"

**Warning signs:**
- High percentage of episodes with >1 cancer category (should be <5% for clean data)
- Treatment episodes assigned to historical cancers patient no longer has
- Drug groupings contradict assigned cancer categories (HL drugs but breast cancer diagnosis)
- Temporal gaps >60 days between episode and assigned diagnosis
- Gantt v2 cancer_category column shows inconsistent categories for same patient's overlapping episodes

**Phase to address:**
Phase 9 (Per-episode cancer categorization) — requires temporal boundary definition and validation

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Reading xlsx at runtime vs. centralizing in R/00_config.R | Faster initial implementation; domain experts edit directly | Non-reproducible results; hidden dependencies; version control gaps | Never for production; OK for one-off exploratory analysis |
| Dropping tumor registry without quantifying impact | Simplifies data quality concerns; faster queries | Unknown coverage loss; undercounting treatment episodes; potential bias | Only after coverage analysis shows <5% unique episodes |
| Patient-level aggregation instead of encounter-level | Simpler dplyr logic; faster development | Clinically meaningless (conflates unrelated events); breaks temporal analysis | Never for treatment/diagnosis linkage; OK for demographic summaries |
| Applying new validation rules without versioning outputs | Single "current" result set; no confusion | Impossible to compare before/after; breaks continuity with prior reports | Never when results feed publications or external reporting |
| Hard-coding ICD ranges (C81.*) vs. explicit exclusions (C81.* EXCEPT C81.0) | Readable syntax; matches clinical shorthand | Breaks when subtypes need separation; silent errors in edge cases | OK for exploratory v1; must refactor when subtype analysis added |
| Manual verification of code mappings vs. automated graph validation | Works for small code sets (<100) | Misses circular references; doesn't scale; error-prone | Only for initial prototype; automate before production |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| NLPHL breakout from HL | Additive logic (add NLPHL category) without removing from HL | Mutually exclusive classification: create NLPHL first, then HL = original EXCLUDING NLPHL codes |
| ICD-9 to ICD-10 mapping (201.4x → C81.0/C81.4) | Assuming 1:1 mapping | SEER conversion shows 201.4 → {C81.0, C81.4}; requires disambiguation logic or multi-value handling |
| External xlsx classification files | read_excel() in each script | Centralize in R/00_config.R following AMC_PAYER_LOOKUP pattern; version-control both xlsx and generated R code |
| Cause of death from DEATH table | SELECT death_cause without quality checks | Profile missingness by payer/site; document limitations; consider external linkage (NDI) or predictive models |
| Encounter-level cancer linkage to episodes | Assume ENCOUNTERID exists for all treatments | Tumor registry dates lack ENCOUNTERID; use +/- 30 day temporal fallback (v1.8 Phase 61 pattern) |
| Replaced-by code verification | Manual spot-checks | Automated graph cycle detection; transitive closure validation; cross-reference official CMS/SEER conversion tables |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Unversioned RDS cache invalidation | Old RDS cache with NLPHL counted in HL used with new code expecting separation | Add version suffix to cache files; add schema hash to cache metadata; invalidate cache when CANCER_SITE_MAP changes | Immediately when breaking changes applied to classification logic |
| Cartesian explosion from multi-cancer episodes | Episode-to-diagnosis join creates duplicate episodes (1 episode × 3 cancers = 3 rows) | Use window functions to select single "primary" cancer per episode; flag multi-cancer cases; test join cardinality | With 7-day gap enforced on all cancers (increases multi-cancer likelihood) |
| Full table scans for replaced-by code lookups | Iterative case_when() on full DIAGNOSIS table (>1M rows) for code resolution | Pre-compute code mapping lookup table; use hash joins; cache resolved codes | When verifying all codes in DIAGNOSIS (~1.5M rows in OneFlorida HL cohort) |
| Reading large xlsx files repeatedly | all_codes_resolved_next_tables.xlsx read in 5+ scripts | Read once in config script; save as RDS; source() in downstream scripts | XLSX >10MB with multiple scripts (cumulative I/O overhead) |
| Smoke test with stale baseline expectations | R/88 smoke test compares to v1.8 counts but v2.1 changes definitions | Update smoke test expectations with each breaking change; document expected deltas; version test fixtures | Every milestone with classification changes |

## Data Quality Patterns

| Issue | Detection | Prevention | Recovery |
|-------|-----------|------------|----------|
| Circular code mappings (A→B→C→A) | Pipeline hangs during code resolution; infinite recursion errors | Graph cycle detection with igraph::is_dag(); transitive closure validation | Manual inspection of replacement chain; revert to official CMS/SEER mappings |
| NLPHL patients in both HL and NLPHL categories | Validation check: sum(nlphl, hl) ≠ original_hl_total | Mutually exclusive classification logic with explicit unit tests | Rebuild classification with exclusion logic; verify with baseline counts |
| Missing cause of death (>40% of deaths) | Profiling: count(is.na(death_cause)) by payer/site | Document limitations; consider external linkage; flag incomplete data in outputs | Augment with NDI/state vital stats; use predictive models; suppress analysis if missingness too high |
| Treatment episodes assigned wrong cancer (temporal mismatch) | Gantt chart review: breast cancer drugs during HL diagnosis window | Use +/- 30 day temporal window; drug grouping cross-validation; domain expert review | Rebuild episode-to-cancer linkage with tighter temporal boundaries; flag ambiguous cases |
| Tumor registry removal drops 30%+ episodes | Compare treatment episode counts before/after source removal | Pre-removal coverage analysis: episodes by source combinations | Restore tumor registry with "lower_confidence" flag; validate against known treatment rates |
| 7-day gap changes cohort population | Total population ≠ 6,347; attrition logs show unexpected drops | Version outputs; document rule changes; regenerate full pipeline from cohort selection | Maintain parallel outputs (gap/no-gap) until validated; update documentation |

## "Looks Done But Isn't" Checklist

- [ ] **NLPHL breakout:** Validation confirms NLPHL + HL_classical = original HL total within ±10 patients
- [ ] **NLPHL breakout:** All scripts with HL filters updated (grep "C81" across codebase shows new exclusion logic)
- [ ] **Tumor registry removal:** Coverage analysis documented showing % episodes from each source combination
- [ ] **Tumor registry removal:** Expected count reduction validated against literature (treatment rates per 100 HL patients)
- [ ] **7-day gap:** Output files versioned (v1 vs v2_7day) with metadata documenting rule change
- [ ] **7-day gap:** Full pipeline regenerated from cohort selection (not just cancer summary scripts)
- [ ] **SCT code 0362:** Analysis scope defined (same encounter / 7-day / 30-day / patient history)
- [ ] **SCT code 0362:** Results validated with manual chart review of 5-10 patients
- [ ] **Replaced-by codes:** Graph cycle detection run with zero cycles found
- [ ] **Replaced-by codes:** Cross-referenced against official SEER ICD-9 to ICD-10 conversion tables
- [ ] **External xlsx tables:** Classification logic centralized in R/00_config.R (not runtime xlsx reads)
- [ ] **External xlsx tables:** Snapshot versioned in git with date stamp and hash
- [ ] **Cause of death:** Missingness profiling completed and documented (% by payer/site)
- [ ] **Cause of death:** HIPAA suppression applied to rare causes (counts 1-10)
- [ ] **Per-episode cancer:** Temporal boundary defined (+/- N days from episode start)
- [ ] **Per-episode cancer:** Multi-cancer episodes handled explicitly (flagged vs. arbitrary selection)
- [ ] **Per-episode cancer:** Drug grouping validation (assigned cancer consistent with drug classes)
- [ ] **All changes:** Smoke test (R/88) updated with new expectations and documented deltas
- [ ] **All changes:** Reference manual (R/89) updated documenting breaking changes
- [ ] **All changes:** Attrition waterfall regenerated showing impact of new rules
- [ ] **All changes:** Payer stratification validated (changes don't create source bias)

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| NLPHL double-counting | MEDIUM | Rebuild CANCER_SITE_MAP with exclusion logic; regenerate all outputs; validate against baseline; update smoke test |
| Tumor registry removal drops 30%+ episodes | HIGH | Restore tumor registry with confidence flags; rebuild treatment episodes; regenerate Gantt v2; validate against literature |
| 7-day gap breaks pre/post counts | MEDIUM | Maintain parallel outputs (gap/no-gap); document differences; regenerate baseline comparisons; update documentation |
| SCT code investigation wrong granularity | LOW | Re-scope analysis with correct join logic; validate with chart review; update results report |
| Circular code mappings | LOW | Use igraph to identify cycles; consult SEER conversion tables; rebuild mapping with validated acyclic graph |
| Runtime xlsx dependency | MEDIUM | Refactor to centralized R config; snapshot xlsx in version control; update all scripts using xlsx; test reproducibility |
| Cause of death quality issues | LOW to MEDIUM | Document limitations; add missingness footnotes; consider external linkage; suppress analysis if >50% missing |
| Per-episode cancer temporal mismatch | MEDIUM | Rebuild episode-cancer linkage with defined temporal window; add drug grouping validation; flag ambiguous cases |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| NLPHL double-counting | Phase 1 (NLPHL breakout implementation) | Unit test: NLPHL + HL_classical = original HL ± 10; smoke test passes |
| Tumor registry removal impact | Phase 2 (Coverage analysis) + Phase 3 (Conditional removal) | Coverage report shows <5% unique TR episodes OR flag-based retention |
| 7-day gap cohort changes | Phase 4 (Gap implementation) | Total population = 6,347; versioned outputs with metadata; documentation updated |
| SCT code 0362 wrong granularity | Phase 5 (SCT investigation) | Manual chart review of 10 patients confirms programmatic definition |
| Circular code mappings | Phase 6 (Replaced-by verification) | igraph::is_dag() returns TRUE; no replacement chains >3 steps |
| Runtime xlsx dependency | Phase 7 (New table creation) | All classifications in R/00_config.R; no readxl::read_excel() in numbered scripts |
| Cause of death quality | Phase 8 (Cause of death integration) | Missingness profiling complete; limitations documented; HIPAA suppression applied |
| Per-episode cancer temporal mismatch | Phase 9 (Episode cancer categorization) | <5% multi-cancer episodes; drug grouping validation; temporal window defined |

## Research Methodology Notes

**Literature-Informed Findings:**
- Tumor registry treatment data shows 47-91% agreement with claims data depending on treatment type and cancer site
- Cause of death requires external linkage to state vital statistics or ML models (86% accuracy reported) for completeness
- ICD-9 code 201.4 maps to BOTH C81.0 (NLPHL) and C81.4 (lymphocyte-rich classical HL) requiring disambiguation
- Temporal gap requirements (7-day) improve specificity but reduce sensitivity in diagnosis confirmation
- Episode-level vs patient-level aggregation is critical for longitudinal cancer data but frequently misimplemented

**Project-Specific Context:**
- Existing pipeline (v2.0, 74 phases) has established patterns for encounter-level cancer linkage (Phase 61)
- CANCER_SITE_MAP in R/00_config.R is centralized configuration following DRY principle (Phase 73)
- Smoke test infrastructure (R/88) and reference manual (R/89) provide validation framework
- RDS caching with FORCE_RELOAD (Phase 15) requires version-aware invalidation for breaking changes
- Payer analysis critical for study objectives requires validation that changes don't introduce source bias

## Sources

**Clinical Cancer Classification:**
- [2026 ICD-10-CM Diagnosis Code C81.0](https://www.icd10data.com/ICD10CM/Codes/C00-D49/C81-C96/C81-/C81.0) - NLPHL code definition
- [ICD-9-CM to ICD-10-CM Conversion SEER](https://seer.cancer.gov/tools/conversion/2014/ICD9CM_to_ICD10CM_2014CF.pdf) - Official 201.4 → C81.0/C81.4 mapping
- [Agreement of Medicare Claims and Tumor Registry Data](https://www.researchgate.net/publication/232163205_Agreement_of_Medicare_Claims_and_Tumor_Registry_Data_for_Assessment_of_Cancer-Related_Treatment) - Treatment source accuracy
- [Completeness of American Cancer Registry Treatment Data](https://pmc.ncbi.nlm.nih.gov/articles/PMC12261666/) - Registry limitations

**Data Quality and Integration:**
- [Leveraging Shannon Entropy to Validate ICD-10 to ICD-11 Transition](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7512330/) - Code mapping validation (86% accuracy, 57% increased uncertainty)
- [Interactive Exploration of Longitudinal Cancer Patient Histories](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7265796/) - Episode-level vs patient-level classification
- [How to ensure backward compatibility in data pipeline framework](https://www.linkedin.com/advice/0/how-can-you-ensure-backward-compatibility-data-yf6of) - Schema evolution and versioning

**Cause of Death Integration:**
- [Enhancing Cause of Death Prediction with ML Models](https://academic.oup.com/jamiaopen/article/9/1/ooaf175/8494398) - 86% accuracy with multimodal data
- [Development of High-Quality Composite Mortality Endpoint](https://onlinelibrary.wiley.com/doi/10.1111/1475-6773.12872) - EHR + external database integration

**Procedure Code Validation:**
- [Coding of Bone Marrow and Stem Cell Transplants](https://libmaneducation.com/coding-of-bone-marrow-transplants-and-stem-cell-transplants/) - SCT code classification
- [Validating Recipients of Pediatric Solid Organ Transplant](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12686849/) - Procedure code validation methodology (91% sensitivity)

**External File Integration:**
- [EasyMergeR for XLSX Files](https://arxiv.org/pdf/2308.04478) - Multi-sheet XLSX handling in R
- [Classification Set File Formats](https://experienceleague.adobe.com/en/docs/analytics/components/classifications/sets/data-files) - XLSX import validation issues
- [Standard Vocabularies for EHR Data](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9472055/) - CCS, LOINC for harmonization

**Pipeline Refactoring:**
- [Data Manipulation in R with dplyr (2026)](https://thelinuxcode.com/data-manipulation-in-r-with-dplyr-2026-practical-patterns-for-clean-reliable-pipelines/) - Common mistakes in 2026
- [Centralized Analytics Platform Maintenance](https://insights.blackcoffer.com/centralized-analytics-platform-for-multi-clinic-healthcare-operations/) - Lookup table management

**Project Context:**
- .planning/PROJECT.md - PCORnet Payer Variable Investigation context
- Existing v1.8-v2.0 implementation patterns (encounter-level cancer linkage Phase 61, DRY consolidation Phase 73)

---
*Pitfalls research for: v2.1 Clinical Data Refinements & NLPHL Breakout*
*Researched: 2026-06-02*
*Confidence: MEDIUM (based on clinical data literature + existing pipeline patterns, limited v2.1-specific precedent)*
