# Project Research Summary

**Project:** PCORnet Payer Variable Investigation — v1.7 Cancer Summary Refinement & Gantt Enhancements
**Domain:** Cancer epidemiology cohort study with clinical timeline visualization (Hodgkin Lymphoma)
**Researched:** 2026-05-22
**Confidence:** HIGH

## Executive Summary

This is a refinement milestone for an existing R-based PCORnet CDM analysis pipeline. The goal is to improve cancer classification fidelity (remove benign neoplasm D-codes), strengthen cohort validation (2+ HL codes with 7-day separation), add temporal filtering (cancers occurring after first HL diagnosis), and enhance Gantt chart interpretability (cancer category labels and death dates). All features are **logic-only enhancements** — no new packages required. The existing validated stack (tidyverse, lubridate, stringr, DuckDB) already provides all necessary capabilities.

**Recommended approach:** Implement in three parallel tracks: (1) D-code filtering in cancer summary scripts (low risk, foundational), (2) HL cohort confirmation and temporal filtering (medium risk, reuses existing 7-day validation pattern from Phase 50), and (3) Gantt enhancements (cancer categories and death dates — independent of tracks 1-2). This separation allows D-code fixes to land quickly while temporal filtering logic is validated. The critical architectural insight is that the numbered-script pattern supports variants (R/53a, R/54a for post-HL filtering) and composable enhancement (R/49 extends without touching upstream scripts).

**Key risks:** (1) Immortal time bias from post-diagnosis filtering (mitigate by producing both filtered and unfiltered outputs, clearly labeling filtered version as exploratory), (2) first HL date calculation must incorporate TUMOR_REGISTRY dates not just DIAGNOSIS (mitigate by querying both sources and taking minimum), and (3) PREFIX_MAP duplication across scripts creates sync risk (mitigate by filtering D-codes at query layer, not by modifying PREFIX_MAP structure). All features use validated patterns from prior phases — risk is integration complexity, not technical capability.

## Key Findings

### Recommended Stack

**NO NEW PACKAGES REQUIRED.** All five new features use the existing validated stack. This is purely a logic enhancement milestone with zero dependency additions and zero integration risk.

**Core technologies already validated:**
- **stringr 1.5.1+**: String pattern matching for D-code filtering (validated in Phase 2 ICD normalization)
- **lubridate 1.9.3+**: Date arithmetic for 7-day separation and temporal filtering (validated in Phase 1 enrollment windows)
- **dplyr 1.2.0+**: Data manipulation for cohort confirmation logic (validated across all cohort scripts)
- **PREFIX_MAP infrastructure**: Cancer category classification already exists in R/53 (tested via cancer_summary_table.xlsx)
- **DuckDB backend**: Table access via get_pcornet_table() for DEMOGRAPHIC/DEATH tables (validated in Phase 30)

**Alternatives considered and rejected:**
- data.table::fread (10-50x faster but opaque syntax conflicts with named predicate requirement)
- New visualization libraries like gtsummary, gt (openxlsx2 already handles styled table output)
- Survival analysis libraries (out of scope — death date is visualization element, not statistical endpoint)

### Expected Features

**Must have (table stakes — missing these = protocol violations):**
- Exclude benign/uncertain D-codes (D10-D48) from cancer classification — ICD-10 Chapter 2 separates malignant from benign neoplasms; cancer registries analyze only malignant
- Cohort confirmation with multiple diagnosis dates — single-code diagnoses may be rule-out/provisional; epidemiology standards require temporal validation (2+ codes 7+ days apart)
- Temporal filtering relative to index cancer diagnosis — secondary cancer analysis requires reference to first HL diagnosis date (SEER methodology standard)
- Death date as clinical endpoint — PCORnet CDM includes DEATH_DATE in DEMOGRAPHIC; death is standard endpoint for cancer timeline visualizations
- Cancer site category labeling — clinical interpretation of treatment episodes requires knowing what cancer is being treated

**Should have (differentiators — add value beyond minimum):**
- Hodgkin-specific binary flag in Gantt data — enables quick visual filtering (color-code HL vs non-HL treatments)
- Temporal filtering with comparison outputs — producing both filtered and unfiltered tables enables validation of filtering logic
- Human-readable code descriptions in Gantt (already implemented in v1.6)

**Defer (anti-features — explicitly do NOT build):**
- Retroactive removal of D-codes from existing v1.6 outputs (breaks reproducibility)
- Death date imputation (PCORnet DEATH_DATE already populated from SSA Death Master File)
- Chemotherapy-specific treatment classification (requires morphology codes not reliably in PCORnet CDM)
- Global minimum gap enforcement for all cancers (2-date + 7-day logic applies ONLY to HL cohort filter)

### Architecture Approach

The v1.7 features integrate cleanly into the existing numbered-script architecture with minimal cross-cutting changes. The numbered-script pattern supports variants (R/53a, R/54a for post-HL filtering) and composable enhancement (R/49 extends without touching R/44a episode generation).

**Major components and modifications:**

1. **Benign D-code removal** — Filter in existing R/53 + R/54 cancer summary scripts (PREFIX_MAP edit or query-layer filter)
2. **HL cohort confirmation** — New script R/56 applies 7-day filter (reuses R/51 pattern), writes confirmed cohort RDS, then R/53/54 join to cohort
3. **Post-HL cancer filtering** — R/53a/R/54a variants read first_hl_dx_date from cohort, filter DIAGNOSIS to DX_DATE > first_hl_date
4. **Gantt cancer category labels** — R/49 enhancement reads cancer_summary.csv, joins on triggering_code → cancer_code, adds category + is_hodgkin flag
5. **Death date integration** — R/00_config.R adds DEATH/DEMOGRAPHIC table path, R/49 joins death_date, exports as pseudo-treatment-type

**Data flow:** DIAGNOSIS → R/56 (cohort confirmation) → R/53 (cancer summary) OR R/53a (post-HL variant) → R/54/R/54a (summary tables). Parallel: PROCEDURES + PRESCRIBING + DIAGNOSIS → R/44a (treatment episodes) → R/49 (Gantt export with cancer categories and death dates). Critical: PREFIX_MAP duplicated across R/47, R/53, R/54 — consider centralizing to R/00_config.R to avoid drift.

### Critical Pitfalls

1. **Shared PREFIX_MAP modification breaks downstream consumers (v1.7-1)** — Removing D-codes from PREFIX_MAP in R/00_config.R breaks all scripts that use it for cancer categorization. **Prevention:** Filter D-codes in query logic (WHERE clause), NOT by removing from PREFIX_MAP. Use `filter(!str_starts(cancer_code, "D"))` rather than modifying shared lookup table.

2. **Immortal time bias from post-diagnosis filtering (v1.7-2)** — Filtering cancer_summary to "cancers after first HL diagnosis" excludes patients who die shortly after HL diagnosis (before accumulating second cancer codes), biasing secondary cancer rates upward. **Prevention:** Produce BOTH versions (all cancers + post-HL cancers), label filtered output as `cancer_summary_post_hl_EXPLORATORY.xlsx`, include denominator note about exclusions. Future mitigation: landmark analysis or time-varying exposure models.

3. **First HL diagnosis date calculation inconsistency (v1.7-4)** — Pipeline calculates first_hl_dx_date from DIAGNOSIS table only, but some patients have earlier HL dates in TUMOR_REGISTRY. Post-HL cancer filtering uses wrong anchor date. **Prevention:** Create `compute_first_hl_date()` function that queries both DIAGNOSIS and TUMOR_REGISTRY, takes minimum date, logs source (DIAGNOSIS/TR/Both).

4. **Death date misidentification (DEMOGRAPHIC vs DEATH table confusion, v1.7-5)** — Code assumes DEMOGRAPHIC table has DEATH_DATE column based on training data, but OneFlorida+ PCORnet CDM v7.0 may use separate DEATH/DEATH_CAUSE tables. **Prevention:** Inspect actual PCORnet schema before implementation (`PRAGMA table_info('DEMOGRAPHIC')`), implement flexible lookup (try DEMOGRAPHIC.DEATH_DATE first, fall back to DEATH table).

5. **7-day gap calculation excludes same-week confirmations (v1.7-7)** — Requiring >= 7 day gap between HL codes excludes patients with codes on Monday and Sunday (6-day gap). **Prevention:** Verify >= 7 vs > 6 day semantics match clinical intent, document rationale for strict interpretation.

## Implications for Roadmap

Based on research, suggested phase structure with three parallel tracks:

### Phase 1: Benign D-Code Removal (Foundation)
**Rationale:** D-code exclusion affects all cancer classification downstream. Must come first. Lowest risk — simple filter predicate. Validates "no new packages" assumption.
**Delivers:** cancer_summary.csv and cancer_summary_table.xlsx with only malignant neoplasms (C00-C96, excluding D10-D48)
**Addresses:** Table stakes feature — exclude benign/uncertain D-codes from cancer classification
**Avoids:** Pitfall v1.7-1 (PREFIX_MAP breaking change) by filtering at query layer, Pitfall v1.7-6 (D-code classification ambiguity) by clarifying in situ (D00-D09) vs benign (D10-D36)
**Implementation:** Modify R/53 and R/54 to add `filter(!str_starts(cancer_code, "D1") & !str_starts(cancer_code, "D2") & !str_starts(cancer_code, "D3") & !str_sub(cancer_code, 1, 3) %in% c("D37", "D38", ..., "D48"))` before cancer summary generation. Re-run to validate Hodgkin Lymphoma % increases to 100% in Column F.

### Phase 2: HL Cohort Confirmation (Parallel Track A)
**Rationale:** Reduces false positives before temporal filtering. Reuses proven pattern from Phase 50 (7-day separation). Required before Phase 3 temporal filtering because filtered output needs valid first HL date.
**Delivers:** confirmed_hl_cohort.rds with columns (ID, first_hl_dx_date, first_hl_dx_source)
**Uses:** lubridate date arithmetic, dplyr group-by-mutate pattern (validated in R/50, R/51)
**Addresses:** Table stakes feature — cohort confirmation with multiple diagnosis dates
**Avoids:** Pitfall v1.7-3 (duplicate HL confirmation logic) by reusing R/51 pattern, Pitfall v1.7-4 (first HL date inconsistency) by querying both DIAGNOSIS and TUMOR_REGISTRY
**Implementation:** Create R/56_hl_cohort_confirmation.R that groups DIAGNOSIS by ID, filters to 2+ HL codes with 7-day gap, computes first_hl_dx_date from min(DIAGNOSIS.DX_DATE, TR.DX_DATE), writes RDS.

### Phase 3: Temporal Filtering (Depends on Phase 2)
**Rationale:** Research question "What other cancers occur after HL?" requires validated first HL date from Phase 2. Deferred until cohort confirmation works. Independent of Gantt enhancements (Phase 4-6).
**Delivers:** cancer_summary_post_hl.csv and cancer_summary_table_post_hl.xlsx (filtered to DX_DATE > first_hl_dx_date), plus unfiltered baseline outputs for comparison
**Uses:** lubridate date comparison, dplyr left_join (validated across all cohort scripts)
**Implements:** R/53a (cancer_summary variant), R/54a (summary table variant)
**Addresses:** Table stakes feature — temporal filtering relative to index cancer diagnosis
**Avoids:** Pitfall v1.7-2 (immortal time bias) by producing both filtered and unfiltered, labeling filtered as EXPLORATORY
**Implementation:** Clone R/53 → R/53a, add temporal filter after line 345. Clone R/54 → R/54a, update input path to cancer_summary_post_hl.csv.

### Phase 4: Gantt Cancer Category Labels (Parallel Track B)
**Rationale:** Human-readability for Gantt charts. Independent of temporal filtering (Phases 2-3). Unblocks clinical review. Requires PREFIX_MAP already tested via Phase 1.
**Delivers:** gantt_detail.csv and gantt_episodes.csv with cancer_category and is_hodgkin columns
**Uses:** PREFIX_MAP infrastructure (already exists in R/53), dplyr left_join (validated in Phase 49 Gantt export)
**Addresses:** Table stakes feature — cancer site category labeling
**Avoids:** Pitfall v1.7-8 (multi-category episodes) by adding cancer_categories_all (comma-separated) + cancer_category_primary, Pitfall v1.7-11 (CSV column breaking change) by adding new columns at end
**Implementation:** Modify R/49 to read cancer_summary.csv, join on (patient_id, triggering_code) = (ID, cancer_code), add category columns, derive is_hodgkin flag.

### Phase 5: Hodgkin Binary Flag (Zero-Cost Derivation)
**Rationale:** Derived from cancer category label (Phase 4). Enables quick visual filtering. Zero computation cost once category exists.
**Delivers:** is_hodgkin column in Gantt CSVs
**Addresses:** Differentiator feature — Hodgkin-specific binary flag
**Avoids:** Pitfall v1.7-10 (redundancy) by deriving in same mutate() call as cancer_category, asserting consistency
**Implementation:** Add `is_hodgkin = as.integer(cancer_category == "Hodgkin Lymphoma")` in R/49 after category join.

### Phase 6: Death Date in Gantt (Parallel Track B, After Phase 4)
**Rationale:** Completes clinical timeline. Independent of temporal filtering. Shows whether patient died during follow-up (essential for survivorship analysis).
**Delivers:** gantt_episodes.csv with death rows (treatment_type = "Death"), gantt_detail.csv with death_date column
**Uses:** DuckDB access to DEMOGRAPHIC/DEATH table (validated in Phase 30), lubridate date parsing (validated in Phase 1)
**Addresses:** Table stakes feature — death date as clinical endpoint
**Avoids:** Pitfall v1.7-5 (DEMOGRAPHIC vs DEATH table confusion) by inspecting schema first and implementing flexible lookup, Pitfall v1.7-9 (death as treatment type model violation) by adding special handling for death pseudo-episodes, Pitfall v1.7-12 (1900 sentinel dates) by applying same nullification as diagnosis dates
**Implementation:** Add DEATH to R/00_config.R PCORNET_TABLES, re-run R/25_duckdb_ingest.R, modify R/49 to join death_date and append death pseudo-episodes.

### Phase Ordering Rationale

- **D-code filtering first (Phase 1):** Affects all cancer classification downstream. Low risk, quick validation. Unblocks everything else.
- **HL cohort confirmation second (Phase 2):** Reduces false positives. Required before temporal filtering (Phase 3). Reuses existing pattern (low risk).
- **Gantt enhancements (Phases 4-6) parallel with temporal filtering (Phase 3):** Independent tracks. Gantt category labels don't depend on cohort confirmation. Can proceed simultaneously.
- **Critical path:** Phase 1 → Phase 2 → Phase 3 (temporal filtering depends on cohort). Phases 4-6 can start after Phase 1 completes.

### Research Flags

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (D-code filtering):** Well-documented ICD-10 structure, simple string matching
- **Phase 2 (HL cohort confirmation):** Reuses existing R/51 pattern, no new research needed
- **Phase 4 (Gantt category labels):** PREFIX_MAP already tested, join pattern standard

**Phases likely needing validation during planning:**
- **Phase 3 (Temporal filtering):** Immortal time bias mitigation requires clinical judgment — validate "exploratory" labeling with oncology collaborator
- **Phase 6 (Death date integration):** PCORnet schema version may vary — inspect actual HiPerGator data before implementation (DEMOGRAPHIC.DEATH_DATE vs separate DEATH table)

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All features use validated stack components from prior phases. No new packages. stringr pattern matching (Phase 2), lubridate date arithmetic (Phase 1), dplyr joins (Phase 3), PREFIX_MAP (Phase 53), DuckDB backend (Phase 30) all tested. |
| Features | HIGH | All table stakes features are standard epidemiology/cancer registry practices with official documentation (SEER, CDC, PCORnet CDM). Implementation complexity low-medium (155 LOC total estimated). |
| Architecture | HIGH | Integration points verified against existing codebase structure. Numbered-script pattern supports variants (R/53a, R/54a) and composable enhancement (R/49 extends without upstream changes). |
| Pitfalls | HIGH | Critical pitfalls (v1.7-1 through v1.7-5) backed by code inspection, official ICD-10/PCORnet documentation, peer-reviewed temporal bias literature. Moderate/minor pitfalls (v1.7-6 through v1.7-12) inferred from common clinical data pipeline patterns. |

**Overall confidence:** HIGH — All features are logic enhancements using validated components. Only uncertainty is DEATH_DATE column population in HiPerGator extract (expected to be populated per VRT partner site mention in PROJECT.md).

### Gaps to Address

- **PREFIX_MAP centralization:** Currently duplicated across R/47, R/53, R/54. Consider extracting to R/00_config.R (same pattern as AMC_PAYER_LOOKUP in Phase 36) to avoid drift. Decision needed: centralize first (separate phase) or accept duplication and document.

- **DEATH_DATE column validation:** Confirm DEATH_DATE column populated in HiPerGator DEMOGRAPHIC table before Phase 6. Test query: `demographic <- get_pcornet_table("DEMOGRAPHIC") %>% select(ID, DEATH_DATE) %>% filter(!is.na(DEATH_DATE)) %>% collect()`. Expected: non-zero count (VRT is death-only partner site per PROJECT.md line 140).

- **Clinical decision on D-code granularity:** Clarify whether to keep D00-D09 (in situ) as clinically relevant and remove only D10-D36 (benign) + D37-D48 (uncertain behavior), OR remove all D-codes. In situ neoplasms (DCIS, melanoma in situ) are clinically significant pre-malignant conditions. Consult oncology collaborator during Phase 1 scoping.

- **Temporal filtering interpretation:** Validate that "exploratory" labeling for post-HL cancer summary is acceptable for insurance disparity analysis use case. Immortal time bias means filtered output cannot be used for causal inference about secondary cancer risk, only exploratory comparison of cancer burden pre- vs post-HL diagnosis.

## Sources

### Primary (HIGH confidence)
- **R/00_config.R, R/01_load_pcornet.R, R/04_build_cohort.R, R/49_gantt_data_export.R, R/50_cancer_site_confirmation.R, R/51_cancer_site_confirmation_7day.R, R/53_cancer_summary.R, R/54_cancer_summary_table.R** — Existing codebase structure, validated patterns, integration points (verified 2026-05-22)
- **PCORnet CDM v6.0/v7.0 Specification** — DEMOGRAPHIC.DEATH_DATE field definition, table structure (https://pcornet.org/wp-content/uploads/2025/05/PCORnet_Common_Data_Model_v70_2025_05_01.pdf)
- **2026 ICD-10-CM Codes C00-D49: Neoplasms** — C-codes (malignant), D00-D09 (in situ), D10-D36 (benign), D37-D48 (uncertain behavior) (https://www.icd10data.com/ICD10CM/Codes/C00-D49)
- **SEER Coding Manual 2026** — Date of first contact, cancer site recoding, subsequent primary cancer methodology (https://seer.cancer.gov/manuals/2026/SPCSM_2026_MainDoc.pdf)
- **CRAN package pages** — dplyr 1.2.1, lubridate 1.9.4, stringr 1.5.2 version verification (accessed 2026-05-22)

### Secondary (MEDIUM confidence)
- **Immortal time bias literature** — Statistical methods for cohort studies, temporal bias in retrospective studies (PMC8478821, PMC8962148, arxiv.org/pdf/2202.02369)
- **Cancer registry validation standards** — 2022 revised European recommendations for coding basis of diagnosis, real-time data validation in cancer registries (PMC10755738, PMC12303076)
- **Data pipeline best practices** — Data contracts for pipeline stability, schema evolution in CDC pipelines, handling breaking changes (acceldata.io, dataskew.io, airbyte.com)

### Tertiary (LOW confidence — needs validation)
- **90-day treatment episode gap methodology** — Oncology claims analysis standard referenced in Real-World Treatment Patterns in Relapsed/Refractory Multiple Myeloma (PMC12301936), but 7-day cohort confirmation threshold not universally mandated (some studies use 30 days)

---
*Research completed: 2026-05-22*
*Supersedes: SUMMARY.md dated 2026-04-21 (v1.6 milestone research; this covers v1.7 additions)*
*Ready for roadmap: yes*
*Next step: Validate DEATH_DATE column in HiPerGator data, clarify D-code granularity with clinical collaborator, then proceed to requirements definition*
