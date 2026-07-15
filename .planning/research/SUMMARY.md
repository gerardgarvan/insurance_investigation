# Project Research Summary

**Project:** PCORnet Payer Variable Investigation -- v3.3 Rituximab/Methotrexate-Associated Diagnoses of Interest
**Domain:** Non-malignant ICD classification + drug co-occurrence attribution layer on an existing oncology cohort R pipeline
**Researched:** 2026-07-15
**Confidence:** HIGH (all findings grounded in direct codebase inspection + FDA-approved indication literature + ICD-10-CM FY2026 tabular verification)

---

## Executive Summary

Milestone v3.3 adds a standalone diagnosis-of-interest (DoI) analysis layer to the existing PCORnet HL-cohort pipeline: detect when a Hodgkin Lymphoma patient's rituximab or methotrexate administration co-occurs with a non-malignant ICD code indicating an autoimmune, inflammatory, or hematologic indication. This is an additive, non-destructive extension -- the cancer cascade, treatment episode logic, and all existing outputs are read-only from v3.3's perspective. The core build pattern is already proven in the codebase: mirror classify_codes() / CANCER_SITE_MAP with parallel classify_doi_codes() / DOI_CODE_MAP structures, and call the existing get_chemo_hits() helper with a new RITDIS_DRUG_RXNORM vector. No new R packages are warranted. renv.lock is unchanged.

The completed, verified code set spans 14 non-malignant clinical categories: Rheumatoid Arthritis, ANCA-Associated Vasculitis (GPA/MPA), Pemphigus/Pemphigoid, Dermatomyositis/Polymyositis, SLE, Sjogren Syndrome, Neurological Autoimmune (NMO, MG, optic neuritis), Hematologic Autoimmune (ITP, AIHA), Psoriasis/PsA, Inflammatory Bowel Disease, and additional EDGE conditions. Five categories were entirely absent from the seed RTF and have been filled by this research: hematologic (ITP D69.3, AIHA D59.1x), connective tissue (SLE M32.x, Sjogren M35.0x), and the full MTX-specific indications (psoriasis L40.x, Crohn K50.x, UC K51.x). Two seed errors require correction before coding begins: I77.82 is actually 'Dissection of artery' in ICD-10-CM (the RTF incorrectly called it 'ANCA-positive vasculitis') and must be excluded; D47.Z2 (Castleman disease) is already classified as a malignancy/near-malignancy in the existing CANCER_SITE_MAP and must be excluded to prevent double-classification.

The most consequential design constraint for v3.3 is the honesty boundary on attribution: this pipeline can only demonstrate co-occurrence, never attribution. Output columns must use 'with [dx]' language, never 'for [dx]'. A three-state likely_non_lymphoma_directed flag (TRUE / FALSE / NA) carries the analytic signal, where NA explicitly represents the ambiguous case -- an HL-active patient whose rituximab or MTX co-occurs with a DoI code and whose clinical interpretation requires chart review. The mutual-exclusivity hard-stop assertion -- sum(is_doi_code(DX) & is_cancer_code(DX)) == 0 -- run before any output is produced, is a non-negotiable design guard.

---

## Key Findings

### Recommended Stack

**Verdict: No new dependencies.** The existing tidyverse + DuckDB + openxlsx2 stack is fully sufficient. The classify_codes() prefix-matching cascade in utils_cancer.R handles all ICD-9/ICD-10 detection requirements already; v3.3 adds two parallel named vectors and two parallel functions. Three evaluated packages were explicitly rejected: icd (100 MB data dependency, C++/Fortran compilation, hierarchy traversal at wrong granularity for a curated set), comorbidity (Charlson/Elixhauser scoring -- wrong problem entirely), and touch (runtime ICD description lookup for a static set that should embed descriptions as names() on the map vector). Runtime RxNorm API calls for rituximab CUI discovery are also rejected -- CUIs are curated once offline from rxnav.nlm.nih.gov and pinned statically in config.

**Core technologies (unchanged):**
- R 4.4.2+ / tidyverse 2.0.0+ -- HiPerGator standard; named predicate style already established
- dplyr 1.2.0+ -- filter() + mutate() for DoI flagging; inner_join + date arithmetic for attribution
- stringr 1.5.1+ -- str_remove() dot normalization; already used in utils_cancer.R
- DuckDB (DBI/dbplyr) -- push prefix filter into SQL before collect(); never load full DIAGNOSIS into R
- openxlsx2 -- 4-sheet Tableau-ready xlsx output; established R/100+ investigation pattern
- checkmate -- assert_character() / assert_data_frame() in new utility functions; v2.0 quality standard

**Critical isolation rule:** Do NOT add rituximab RxNorm CUIs to TREATMENT_CODES$chemo_rxnorm -- this would inflate chemo detection counts and corrupt ABVD/BV+AVD regimen identification. Use a new RITDIS_DRUG_RXNORM list that references existing MTX CUIs by name and adds rituximab CUIs additively. Do NOT modify DRUG_GROUPINGS J9310/J9311/J9312 from "Chemotherapy" -- those entries are correct for the cancer pipeline and must remain unchanged.

### Expected Features

**Must have (table stakes) -- FDA-approved or major-guideline-supported:**

| Code Set | ICD-10 Prefix | ICD-9 | Drug | Capture Strategy |
|----------|--------------|-------|------|------------------|
| Rheumatoid Arthritis | M05, M06 | 714 | RTX+MTX | 3-char prefix |
| GPA (Wegener) | M31.30, M31.31, M31.39 | 446.4 | RTX | 4-char prefix M313 |
| MPA | M31.7 | 447.8 | RTX | Specific code |
| Pemphigus vulgaris + variants | L10 (all) | 694.4 | RTX | 3-char prefix L10 |
| Cicatricial pemphigoid (MMP) | L12 | 694.5, 694.6x | RTX | 3-char prefix L12 |
| SLE | M32 | 710.0 | RTX+MTX | 3-char prefix M32 |
| ITP | D69.3, D69.41 | 287.31 | RTX | Specific codes (D693 4-char key) |
| Warm-AIHA / Cold agglutinin | D59.1x | 283.0 | RTX | 4-char prefix D591 |
| NMO/Devic | G36.0 | 341.0 | RTX | Specific code |
| Dermatomyositis/PM | M33 | 710.3, 710.4 | MTX+RTX | 3-char prefix M33 |
| Psoriasis / PsA | L40 | 696.0, 696.1 | MTX | 3-char prefix L40 |
| Crohn disease | K50 | 555.x | MTX | 3-char prefix K50 |

**Should have (differentiators / EDGE indications):**
- Cold agglutinin disease (D59.12) -- FY2023 expansion, distinct from warm-AIHA
- Myasthenia gravis (G70.00, G70.01) -- RTX increasingly used; gap in most payer databases
- Sjogren syndrome (M35.0x / M350 4-char prefix) -- RTX for systemic manifestations
- Cryoglobulinemic vasculitis (D89.1) -- RTX preferred; often missed in code sets
- Skin-limited vasculitis (L95.8, L95.9) -- RTX for refractory leukocytoclastic vasculitis
- Ulcerative colitis (K51) -- MTX EDGE tier (less evidence than Crohn)
- IgA vasculitis (D69.2) -- RTX in severe nephritis; 4-char key D692 disambiguates from D693 (ITP)

**Anti-features (codes to explicitly exclude):**
- I77.82 -- The RTF called this 'ANCA-positive vasculitis'; it is 'Dissection of artery' in ICD-10-CM FY2026. Most critical seed error. Use M31.30/M31.31/M31.7 for GPA/MPA.
- D47.Z2 (Castleman disease) -- Already in CANCER_SITE_MAP under D47 = 'MDS/Myeloproliferative.' Double-classification is a hard error.
- L10.81 (Paraneoplastic pemphigus) -- Include code but attach paraneoplastic_flag = TRUE column; in HL cohort, L10.81 is nearly always a cancer complication, not an independent autoimmune rituximab indication.
- H46.2 (Nutritional optic neuropathy) and H46.3 (Toxic optic neuropathy) -- Not autoimmune; use 4-char prefix H460, H461, H468, H469 rather than 3-char H46.
- M30.1 (EGPA/Churg-Strauss) -- Mepolizumab now FDA-preferred; RTX only off-label. Include as LOW-confidence EDGE only.

**Three-state flag design (do not simplify to two-state):**

The likely_non_lymphoma_directed column takes three values:
- TRUE: drug co-occurs with DoI dx AND no active HL in same +-90-day window
- NA: HL also active in same window (ambiguous; reviewer discretion required)
- FALSE: no drug co-occurrence found in window

Collapsing NA to FALSE silently undercounts the most clinically interesting ambiguous cases.

### Architecture Approach

The DoI layer is a parallel analysis system, not an extension of the cancer cascade. It runs in a single new investigation script (R/111_doi_attribution_report.R) that reads existing RDS artifacts (treatment_episode_detail.rds from R/26) and queries the DIAGNOSIS table via DuckDB. Two cached outputs are produced: doi_encounters.rds (encounter-grain: one row per PATID x ENCOUNTERID x doi_code) and doi_patients.rds (patient-grain summary). A 4-sheet Tableau-ready xlsx is the deliverable. Six files are touched in total -- two new, four modified -- and the cancer cascade files (utils_cancer.R, R/28, treatment_episodes.rds) are strictly read-only.

**New and modified files:**

1. R/00_config.R (MODIFIED) -- Section 4c: DOI_CODE_MAP (ICD-10 and ICD-9 prefix entries, named character vector mirroring CANCER_SITE_MAP); Section 4d: RITUXIMAB_CODES, MTX_CODES, DOI_ATTRIBUTION_WINDOW_DAYS <- 90L
2. R/utils/utils_doi.R (NEW) -- is_doi_code(dx) and classify_doi_codes(codes): strict structural mirrors of is_cancer_code() / classify_codes(); auto-sourced via existing utils glob in R/00_config.R
3. R/111_doi_attribution_report.R (NEW) -- Complete investigation script: DuckDB DIAGNOSIS pull -> DoI classification -> attribution join (ENCOUNTERID-first tier 1, +-90-day PATID temporal tier 2) -> likely_non_lymphoma_directed derivation -> 4-sheet xlsx
4. R/39_run_all_investigations.R (MODIFIED) -- +1 entry in investigation_scripts, +1 in expected_xlsx
5. R/SCRIPT_INDEX.md (MODIFIED) -- +1 row for R/111
6. R/88_smoke_test_comprehensive.R (MODIFIED) -- New section [30/30] with 10 checks including the mutual-exclusivity hard-stop assertion

**Attribution join -- two-tier:**
- Tier 1 (higher confidence): ENCOUNTERID direct match -- drug and DoI diagnosis share the same visit
- Tier 2 (broader): PATID + abs(DX_DATE - treatment_date) <= 90L temporal window

**+-90-day window rationale:** Rituximab maintenance for autoimmune conditions is every 6 months; clinical re-assessment is quarterly. MTX for IBD/psoriasis is re-assessed at 12-week intervals. +-30 days (the cancer cascade window) would miss the vast majority of legitimate autoimmune co-occurrences. +-180 days exceeds one rituximab dosing cycle and introduces unacceptable noise. DOI_ATTRIBUTION_WINDOW_DAYS is a named constant in config -- not a hardcoded magic number -- and is documented in the xlsx Metadata sheet for SME review.

### Critical Pitfalls

1. **I77.82 seed error -- exclude, do not implement.** The seed RTF cited I77.82 as 'ANCA-positive vasculitis.' ICD-10-CM FY2026 codes I77.82 as 'Dissection of artery' -- an entirely unrelated non-inflammatory vascular injury. The correct GPA codes are M31.30/M31.31/M31.39; the correct MPA code is M31.7.

2. **D47.Z2 Castleman disease -- cancer cascade hard-stop.** D47 is already mapped in CANCER_SITE_MAP as 'MDS/Myeloproliferative.' Adding D47.Z2 to DOI_CODE_MAP creates double-classification. The mutual-exclusivity assertion sum(is_doi_code(DX) & is_cancer_code(DX)) == 0 (run as a hard-stop before any output) catches this and any future accidental overlaps. This assertion must also appear in the R/88 smoke test.

3. **L10.81 paraneoplastic pemphigus -- flag, do not exclude.** Include the code in DOI_CODE_MAP but attach a paraneoplastic_flag = TRUE marker in R/111. In an HL cohort, paraneoplastic pemphigus is typically a cancer complication, not an independent autoimmune rituximab indication. Leaving it unflagged inflates the 'Pemphigus' category with cancer-related codes.

4. **Co-occurrence, not attribution -- enforce in naming and prose.** Output columns must use 'with [dx]' language, never 'for [dx]'. Every output sheet must carry the CAVEATS footnote: 'Co-occurrence does not imply treatment attribution. Clinical chart review required for confirmation.' Code-review gate: reject any output column named rituximab_for_* or mtx_reason_*.

5. **ICD-9/ICD-10 DX_TYPE gating -- never mix in a single undifferentiated prefix lookup.** The classifier must partition by DX_TYPE ('09' / '10') before prefix matching, mirroring is_hl_diagnosis() in utils_icd.R. DX_TYPE can also be NA or 'SM' (SNOMED) in PCORnet; handle those as FALSE in is_doi_code().

6. **D69 disambiguation via 4-char prefix keys.** D69.2 (IgA vasculitis) and D69.3 (ITP) share the 3-char prefix D69. DOI_CODE_MAP must use 4-char keys 'D692' (Vasculitis) and 'D693' (Hematologic Autoimmune) and the classifier must try the 4-char key before the 3-char key -- identical to the C810/C81 cascade in CANCER_SITE_MAP.

7. **MTX attribution false-positives -- high-dose IV vs. low-dose oral are indistinguishable by RXNORM alone.** Flag temporal directionality (MTX predating HL diagnosis by >6 months is a likely pre-existing autoimmune signal), never claim attribution, and expose dose/route columns from PRESCRIBING/MED_ADMIN if available.

8. **DuckDB-native prefix filter -- never load full DIAGNOSIS into R.** Push the prefix filter into DuckDB SQL (WHERE LEFT(DX, 3) IN (...)) and collect() only the filtered subset. Loading full DIAGNOSIS into R will OOM on HiPerGator with a multi-million-row table.

9. **HIPAA small-cell suppression on rare DoI categories.** NMO (~1-4 per 100k), pemphigus vulgaris (~1 per 100k), GPA/Wegener (~3 per 100k) -- in a Hodgkin cohort, these will produce cells of 0-5. The suppress_small() helper (threshold = 11L, pattern from R/57) must cover all n_patients and n_encounters columns in Sheet 3. Rare ANCA sub-categories may need merging if individual counts are <11.

10. **Dual-environment runtime gate -- HiPerGator confirmation is part of the definition of done.** R/88 smoke test section must include an IS_LOCAL-gated block that queries the real DIAGNOSIS table and logs DoI hit counts. Phase transition notes must explicitly record HiPerGator runtime confirmation.

---

## Implications for Roadmap

Based on the research, v3.3 decomposes cleanly into four phases following strict dependency order. Phase 1 is the prerequisite; Phases 2 through 4 can be time-boxed in a single sprint once Phase 1 is complete.

### Phase 1: Code-Set and Infrastructure Centralization

**Rationale:** All downstream code depends on DOI_CODE_MAP being correct and the utility functions existing. The seed has documented gaps and one critical seed error (I77.82). These must be resolved before any classification script is written.

**Delivers:**
- R/00_config.R Section 4c: DOI_CODE_MAP (ICD-10 and ICD-9) with all 14 categories complete, RITDIS_CODE_VERSION constant, inline audit comments per code group
- R/00_config.R Section 4d: RITUXIMAB_CODES, MTX_CODES (referencing existing CUIs by name), DOI_ATTRIBUTION_WINDOW_DAYS <- 90L
- R/utils/utils_doi.R: is_doi_code() and classify_doi_codes() with checkmate input validation
- Fixture augmentation: at least one patient with an ICD-10 DoI code and one with the ICD-9 equivalent

**Implements from features:** Fills all 5 seed gaps (hematologic, connective tissue, GPA/MPA, MG, MTX-specific). Excludes I77.82, D47.Z2.

**Avoids:** Pitfalls 1 (ICD-9/10 collision), 2 (dotted/undotted mismatch), 5 (MTX CUI contamination of chemo detection), 12 (code-set incompleteness).

**Research flag:** No additional research needed -- FEATURES.md provides the complete verified code set. Implementation is a transcription task from research to config constants.

---

### Phase 2: DoI Classification Script (R/111, Sections 1-5)

**Rationale:** With the code map and utils in place, the DuckDB query and classification logic can be built and validated. The mutual-exclusivity hard-stop assertion must run here before any outputs are produced.

**Delivers:**
- R/111_doi_attribution_report.R Sections 1-5: config sourcing, DuckDB DIAGNOSIS pull with DuckDB-native prefix filter, is_doi_code() / classify_doi_codes() application, the !is_cancer_code(DX) guard, doi_encounters.rds and doi_patients.rds cached artifacts
- Hard-stop assertion: sum(is_doi_code(DX) & is_cancer_code(DX)) == 0 -- script halts if non-zero
- tabyl(doi_category) counts reviewed against clinical prevalence expectations (RA should dominate; NMO, pemphigus rare)

**Uses:** utils_doi.R (Phase 1), DuckDB backend, DX_TYPE gating, D69 4-char disambiguation.

**Avoids:** Pitfalls 3 (prefix over-capture caught by tabyl review), 4 (cancer cascade overlap -- hard-stop assertion), 7 (DIAGNOSIS as primary source, not CONDITION), 10 (DuckDB-native filter prevents OOM).

**Research flag:** Standard pattern (mirrors R/104/R/105/R/106). No additional research needed.

---

### Phase 3: Attribution Linkage and Output Design (R/111, Sections 6-9)

**Rationale:** Attribution logic depends on doi_encounters.rds existing (Phase 2). The +-90-day window design and column naming convention must be locked here before any report prose is written. This is the highest-risk phase for clinical validity violations.

**Delivers:**
- R/111 Sections 6-9: Two-tier attribution join (ENCOUNTERID-first, then +-90-day PATID temporal), near_rituximab / near_mtx logical flags, attribution_method column (encounter_id / temporal_window / none), likely_non_lymphoma_directed three-state flag
- 4-sheet xlsx: Sheet 1 (Patient Prevalence), Sheet 2 (Encounter Co-occurrence), Sheet 3 (Drug x DoI Summary with HIPAA suppression), Sheet 4 (Metadata with window documentation)
- paraneoplastic_flag column on Sheet 2 for L10.81 encounters
- CAVEATS footnote on every sheet

**Avoids:** Pitfalls 5 (MTX attribution false-positives -- co-occurrence language enforced), 6 (temporal window as named constant), 8 (clinical validity over-claiming), 9 (HIPAA suppression on all count columns).

**Research flag:** The +-90-day window choice should be reviewed with the clinical SME before xlsx is finalized. Include a lookback sensitivity note in the Metadata sheet (+-30-day and +-180-day counts for comparison).

---

### Phase 4: Registration, Smoke Test, and HiPerGator Runtime Confirmation

**Rationale:** Script and output registration are separate from implementation and can proceed in parallel with Phase 3 once R/111 structure is stable. HiPerGator runtime confirmation is the definition-of-done gate for v3.3.

**Delivers:**
- R/39_run_all_investigations.R: R/111 added to investigation_scripts and expected_xlsx
- R/SCRIPT_INDEX.md: R/111 row added
- R/88_smoke_test_comprehensive.R Section [30/30]: 10 checks covering DOI_CODE_MAP existence, no-overlap with cancer maps (hard-stop), is_doi_code() / classify_doi_codes() spot-checks, utils_doi.R and R/111 file existence, IS_LOCAL-gated HiPerGator runtime check
- HiPerGator runtime confirmation logged in phase transition notes

**Avoids:** Pitfalls 10 (dual-environment gap), 11 (smoke-test staleness).

**Research flag:** Standard registration pattern. No additional research needed.

---

### Phase Ordering Rationale

- Phase 1 is a strict prerequisite for Phases 2-4: DOI_CODE_MAP must exist before any classification code is written.
- Phase 2 is a strict prerequisite for Phase 3: doi_encounters.rds must exist before attribution joins.
- Phases 3 and 4 have overlapping work and can proceed in parallel once Phase 2 DuckDB classification output is verified.
- The mutual-exclusivity hard-stop assertion in Phase 2 is the most important single check in v3.3 -- it guarantees the cancer cascade is never contaminated.

### Research Flags

Phases with well-documented patterns -- additional research not needed:
- **Phase 1:** Code map transcription from research to config. Pattern established; all codes verified in FEATURES.md.
- **Phase 2:** Mirrors classify_codes() / is_cancer_code() exactly. Pattern established in utils_cancer.R.
- **Phase 4:** Registration and smoke-test patterns established in R/39 and R/88. No novelty.

Phases that benefit from SME review during planning:
- **Phase 3:** The +-90-day attribution window and the likely_non_lymphoma_directed three-state flag semantics should be reviewed with the clinical investigator before the xlsx is finalized.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Direct codebase inspection confirmed all integration points; no new packages needed; renv.lock unchanged |
| Features -- table-stakes codes | HIGH | FDA-approved indications verified; ICD-10-CM FY2025 tabular verified; cancer map overlap verified against R/00_config.R |
| Features -- EDGE codes | MEDIUM | Published clinical evidence but not FDA-approved; RTX dose/indication ambiguity is inherent to claims data |
| Features -- ICD-9 equivalents | MEDIUM | Standard GEMS crosswalk patterns; pre-2015 codes verified for primary conditions; EDGE ICD-9 LOW confidence until runtime |
| Architecture | HIGH | All patterns derived from direct codebase inspection; no inference required |
| Pitfalls | HIGH | Project-specific pitfalls derived from known failure modes in this codebase (Phase 100 CONDITION table finding, Phase 126 smoke-test attestation gap, Phase 124 MED_ADMIN RXNORM_CUI mismatch) |

**Overall confidence: HIGH**

### Gaps to Address During Implementation

- **Rituximab RxNorm CUI enumeration:** Ingredient CUI 121191 confirmed (MEDIUM confidence). Product-level CUIs must be enumerated manually from RxNav browser before Phase 1 config commit. One-time curation step, not a recurring task.
- **D59.1 vs D59.1x granularity in real extract:** ICD-10-CM FY2023 expanded D59.1 into D59.11/D59.12/D59.13/D59.19. Older records will have D59.1 (legacy). The 4-char prefix key 'D591' captures both forms; verify at runtime.
- **HiPerGator DIAGNOSIS table column name:** DX_TYPE confirmed in PCORnet CDM v7.0 spec and existing pipeline code. Some PCORnet extracts use DX_TYPE_CD. Phase 2 DuckDB query should log actual column name from DBI::dbListFields().
- **EGPA (M30.1) ICD-9 ambiguity:** ICD-9 446.4 was used for both GPA and EGPA in ICD-9. Document in config comments and use 446.4 for GPA only.
- **Fixture augmentation scope:** The current 20-patient fixture is insufficient to exercise HIPAA suppression logic. Either augment the fixture or accept that suppression can only be verified at HiPerGator runtime.

---

## Sources

### Primary (HIGH confidence -- direct codebase inspection)
- R/00_config.R -- CANCER_SITE_MAP, ICD9_CANCER_SITE_MAP, DRUG_GROUPINGS, TREATMENT_CODES$chemo_rxnorm, AMC_PAYER_LOOKUP -- classifier constant patterns verified
- R/utils/utils_cancer.R -- is_cancer_code(), classify_codes() 4-tier cascade structure confirmed
- R/utils/utils_icd.R -- is_hl_diagnosis() DX_TYPE-gated pattern (correct template for is_doi_code())
- R/utils/utils_treatment.R -- get_chemo_hits() signature confirmed; accepts any chemo_rxnorm vector
- R/28_episode_classification.R -- ENCOUNTERID-first + 30-day temporal fallback pattern
- R/100_ruca_rurality_summary.R -- R/100+ investigation script convention
- .planning/PROJECT.md -- HIPAA suppression requirement, dual-environment constraint, Phase 100 CONDITION table finding
- .planning/research/ritdis_seed_codes.md -- seed code set with documented gaps

### Primary (HIGH confidence -- official clinical/regulatory sources)
- FDA rituximab (Rituxan) prescribing information -- approved indications: RA (2006), GPA/MPA (2011), pemphigus vulgaris (2018)
- ICD-10-CM FY2025 Tabular List (CMS, effective Oct 2024) -- all M/L/D/G/K/I prefix code families verified
- ICD-10-CM FY2023 expansion notes -- D59.1x AIHA granularity; M35.0x Sjogren expansion
- PCORnet CDM v7.0 specification -- DIAGNOSIS table grain (DX_TYPE 09/10), CONDITION table grain

### Secondary (MEDIUM confidence -- guideline literature)
- ACR guidelines for biologic DMARDs in RA (2022) -- RTX+MTX combination standard
- EULAR ANCA-associated vasculitis recommendations (2022) -- RTX FDA-approved GPA/MPA
- ASH ITP guidelines (2019, 2021 update) -- RTX second-line confirmed
- ASH AIHA guidelines (2021) -- RTX first-line for warm-AIHA and cold agglutinin disease
- ECCO Crohn disease guidelines (2023) -- MTX second-line immunomodulator
- International Pemphigus and Pemphigoid Foundation guidelines (2023)
- NLM RxNav (rxnav.nlm.nih.gov) -- rituximab ingredient CUI 121191 (MEDIUM; product-level CUIs require manual enumeration)

---
*Research completed: 2026-07-15*
*Ready for roadmap: yes*
