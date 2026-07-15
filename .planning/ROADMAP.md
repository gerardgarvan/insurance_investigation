# Roadmap: PCORnet Payer Variable Investigation (R Pipeline)

## Milestones

- ✅ **v1.0 MVP** - Phases 1-14 (shipped 2026-04-01)
- ✅ **v1.1 RDS Cache & Visualization Polish** - Phases 15-17 (shipped 2026-04-03)
- ✅ **v1.2 Multi-Source Overlap Investigation** - Phases 19-25 (on hold)
- ✅ **v1.3 DuckDB Backend Migration** - Phases 29-32 (shipped 2026-04-23)
- ✅ **v1.4 AV+TH Subset Analysis** - Phase 33 (shipped 2026-04-27)
- ✅ **v1.5 Payer Analysis Expansion** - Phases 34-37 (shipped 2026-05-01)
- ✅ **v1.6 Treatment Code Validation & Cancer Site Analysis** - Phases 45-54 (shipped 2026-05-22)
- ✅ **v1.7 Cancer Summary Refinement & Gantt Enhancements** - Phases 55-59 (shipped 2026-05-28)
- ✅ **v1.8 Episode-Level Cancer Linkage & First-Line Therapy Identification** - Phases 60-63 (shipped 2026-06-01)
- ✅ **v2.0 Codebase Cleanup & Documentation** - Phases 65-74 (shipped 2026-06-02)
- ✅ **v2.1 Clinical Data Refinements & NLPHL Breakout** - Phases 75-82 (shipped 2026-06-03)
- ✅ **v2.2 Local Testing Infrastructure & Clinical Refinements** - Phases 83-89 (shipped 2026-06-05)
- ✅ **v2.3 Gantt Data Enrichment** - Phases 90-94 (shipped 2026-06-08)
- ✅ **v3.0 data.table Infrastructure** - Phases 95-99 (shipped 2026-06-11)
- ✅ **v3.1 Meeting Gap Closure — Clinical Data Coverage** - Phases 100-103 (shipped 2026-06-12)
- ✅ **v3.2 Meeting Gap Resolution Report** - Phases 104-126 (shipped 2026-07-15)
- 🚧 **v3.3 Rituximab/Methotrexate-Associated Diagnoses of Interest** - Phases 127-130 (in progress)

## Phases

<details>
<summary>✅ v1.0 through v3.2 (Phases 1-126) - SHIPPED 2026-07-15</summary>

See MILESTONES.md for full details on all shipped milestones.

126 phases completed across 16 milestones. Key capabilities delivered:
- PCORnet CDM loading, payer harmonization, cohort filter chain
- DuckDB backend with dual-environment support (HiPerGator + Windows)
- data.table infrastructure with 6 keyed lookup tables
- Treatment episodes with encounter-level cancer linkage and regimen identification
- Unified ICD-9/ICD-10 cancer code handling via utils_cancer.R
- Instance-level drug grouping tables, consolidated Gantt export
- MED_ADMIN/DISPENSING chemo-detection fix (+1,328 patients / +13,762 chemo dates)
- Comprehensive smoke test (R/88) exits 0 on HiPerGator

</details>

### 🚧 v3.3 Rituximab/Methotrexate-Associated Diagnoses of Interest (In Progress)

**Milestone Goal:** Identify the non-malignant diagnoses that rituximab and methotrexate treat (autoimmune, inflammatory, hematologic), add them as a new diagnosis-of-interest (DoI) class distinct from the cancer cascade, and use them to disambiguate treatment attribution — flagging when a patient's rituximab/MTX co-occurs with a non-lymphoma condition. The cancer cascade and all existing outputs are read-only throughout.

## Phases (v3.3)

- [ ] **Phase 127: Code-Set and Infrastructure Centralization** (2 plans) - DOI_CODE_MAP + utils_doi.R + fixture augmentation
- [ ] **Phase 128: DoI Classification** - DuckDB DIAGNOSIS pull, classify, mutual-exclusivity hard-stop, cached artifacts
- [ ] **Phase 129: Attribution Linkage and Output** - Two-tier join, three-state flag, 4-sheet xlsx, HIPAA suppression
- [ ] **Phase 130: Registration, Smoke Test, and HiPerGator Runtime** - R/39 + SCRIPT_INDEX + R/88 section + runtime gate

## Phase Details

### Phase 127: Code-Set and Infrastructure Centralization
**Goal**: All downstream DoI classification code has a correct, complete, versioned code map and a tested utility layer to match against
**Depends on**: Phase 126 (v3.3 starting point — cancer cascade unchanged)
**Requirements**: DOI-CODE-01, DOI-CODE-02, DOI-CODE-03, DOI-CODE-04, DOI-CLASS-01, DOI-QA-04

**Design constraints:**
- DOI_CODE_MAP placed in R/00_config.R Section 4c, mirroring CANCER_SITE_MAP structure (3-char and 4-char prefix keys)
- D69 disambiguation via 4-char keys (D692 = IgA vasculitis, D693 = ITP) mirroring C810/C81 NLPHL precedent
- RITUXIMAB_CODES, MTX_CODES, and DOI_ATTRIBUTION_WINDOW_DAYS (90L) placed in Section 4d — separate from TREATMENT_CODES$chemo_rxnorm to prevent chemo-detection contamination
- utils_doi.R auto-sourced via R/00_config.R utils glob — zero additional config changes needed
- is_doi_code() must gate on DX_TYPE ("09"/"10") before prefix matching, mirroring is_hl_diagnosis() — never mix systems in one undifferentiated lookup
- I77.82 explicitly excluded (seed error: "Dissection of artery", not ANCA vasculitis)
- D47.Z2 explicitly excluded (already owned by CANCER_SITE_MAP as MDS/Myeloproliferative)
- RITDIS_CODE_VERSION constant pinned to FY2026 with inline audit comments per code group
- Fixture: at least one ICD-10 DoI patient (e.g., M05.9 RA) and one ICD-9 DoI patient (e.g., 714.0 RA) added to test fixtures

**Success Criteria** (what must be TRUE):
  1. DOI_CODE_MAP exists in R/00_config.R with all 14 clinical categories: RA, GPA/MPA vasculitis, pemphigus, pemphigoid, inflammatory myopathy, neurological autoimmune, hematologic autoimmune, SLE, Sjogren's, psoriasis, IBD, and EDGE conditions — including the five categories absent from the seed RTF (hematologic, SLE, Sjogren's, GPA codes, MTX-specific IBD/psoriasis)
  2. I77.82 is absent from DOI_CODE_MAP with an inline exclusion comment; D47.Z2 is absent with a cancer-cascade-conflict comment
  3. is_doi_code("M05.9") returns TRUE and is_doi_code("C81.90") returns FALSE; DX_TYPE gating prevents ICD-9/ICD-10 numeric collision
  4. RITUXIMAB_CODES and MTX_CODES vectors exist and do not appear in TREATMENT_CODES$chemo_rxnorm or DRUG_GROUPINGS — no chemo-detection contamination
  5. Local test fixture exercises is_doi_code() on at least one ICD-10 and one ICD-9 DoI code without errors
**Plans**: 2 plans
- [x] 127-01-PLAN.md — R/00_config.R Section 4c (DOI_CODE_MAP, DOI_CODE_TIER, RITDIS_CODE_VERSION) + Section 4d (RITUXIMAB_CODES, MTX_CODES, DOI_ATTRIBUTION_WINDOW_DAYS) [DOI-CODE-01/02/03/04] (Wave 1)
- [ ] 127-02-PLAN.md — R/utils/utils_doi.R (is_doi_code DX_TYPE-gated + classify_doi_codes) + DIAGNOSIS fixture augmentation (ICD-10 M05.9, ICD-9 714.0) [DOI-CLASS-01, DOI-QA-04] (Wave 2, depends on 127-01)

### Phase 128: DoI Classification
**Goal**: Encounter-level and patient-level DoI classification artifacts are produced from the real DIAGNOSIS table with a hard guarantee that no oncology code leaks into the DoI layer
**Depends on**: Phase 127
**Requirements**: DOI-CLASS-02, DOI-CLASS-03, DOI-CLASS-04, DOI-CLASS-05

**Design constraints:**
- DuckDB-native prefix filter pushes WHERE LEFT(DX, 3) IN (...) into SQL before collect() — never load full DIAGNOSIS table into R (OOM risk on HiPerGator with multi-million-row tables)
- Mutual-exclusivity hard-stop: sum(is_doi_code(DX) & is_cancer_code(DX)) == 0 runs before any output is produced; script halts if non-zero
- L10.81 (paraneoplastic pemphigus) included in classification but receives paraneoplastic_flag = TRUE — not silently treated as an independent autoimmune indication
- doi_encounters.rds: one row per (PATID, ENCOUNTERID, DX_DATE, doi_code, doi_category)
- doi_patients.rds: one row per PATID (has_any_doi, doi_categories ascending, doi_first_date, doi_last_date, n_doi_encounters)
- utils_cancer.R, R/28, and treatment_episodes.rds are strictly read-only from R/111's perspective
- tabyl(doi_category) count review confirms clinical plausibility (RA should dominate; NMO and pemphigus should be rare)

**Success Criteria** (what must be TRUE):
  1. doi_encounters.rds is produced with encounter-level DoI flags; doi_patients.rds is derived from it at patient grain — both cached in the standard output cache directory
  2. The mutual-exclusivity assertion sum(is_doi_code(DX) & is_cancer_code(DX)) == 0 fires correctly and halts the script if any code maps to both layers — zero tolerance for double-classification
  3. Encounters carrying L10.81 (paraneoplastic pemphigus) have paraneoplastic_flag = TRUE in doi_encounters, distinguishable from primary autoimmune pemphigus
  4. The DIAGNOSIS DuckDB query uses a native prefix filter (LEFT(DX, ...) IN (...)) and does not load the full DIAGNOSIS table into R memory
**Plans**: TBD

### Phase 129: Attribution Linkage and Output
**Goal**: Drug co-occurrence linkage is produced with honest three-state attribution semantics, HIPAA suppression applied, and co-occurrence language enforced throughout all four output sheets
**Depends on**: Phase 128
**Requirements**: DOI-ATTR-01, DOI-ATTR-02, DOI-ATTR-03, DOI-OUT-01, DOI-OUT-02, DOI-OUT-03

**Design constraints:**
- Two-tier join: ENCOUNTERID direct match (tier 1, higher confidence) before ±90-day PATID temporal window (tier 2) — mirrors R/28 D-01/D-02 pattern; DOI_ATTRIBUTION_WINDOW_DAYS is the named constant, not a magic number
- Three-state likely_non_lymphoma_directed: TRUE (drug co-occurs with DoI AND no HL active in same window) / NA (HL also active in same ±90-day window — ambiguous) / FALSE (no drug co-occurrence) — NA must NOT be silently collapsed to FALSE
- attribution_method column: "encounter_id" / "temporal_window" / "none" — records how each link was established
- All column names and all prose use "with [dx]" language, never "for [dx]" — no output column named rituximab_for_* or mtx_reason_*
- CAVEATS footnote on every sheet: "Co-occurrence does not imply treatment attribution. Clinical chart review required for confirmation."
- HIPAA suppression: suppress_small() (threshold 11L) applied to every n_patients and n_encounters column in Sheet 3 before xlsx write — rare DoI categories (NMO, pemphigus, GPA) expected to produce single-digit cells
- Metadata sheet documents ±90-day window with ±30-day and ±180-day sensitivity comparison counts for SME review
- drug co-occurrence reads from treatment_episode_detail.rds (read-only) filtered to RITUXIMAB_CODES | MTX_CODES — no additional DuckDB query for drug administrations

**Success Criteria** (what must be TRUE):
  1. A 4-sheet Tableau-ready xlsx (doi_attribution_report.xlsx) is produced: Sheet 1 Patient Prevalence, Sheet 2 Encounter Co-occurrence with attribution_method column, Sheet 3 Drug x DoI Summary with HIPAA-suppressed counts, Sheet 4 Metadata with window documentation
  2. likely_non_lymphoma_directed is a three-state logical column (TRUE / FALSE / NA) — NA represents ambiguous cases where HL is also active in the same ±90-day window; no NA values are silently coerced to FALSE
  3. Every count column (n_patients, n_encounters) in Sheet 3 passes through suppress_small() before write — cells with values 1-10 appear as "<11", never as raw integers
  4. No output column name contains "_for_" (causal language); all drug-diagnosis relationship columns use "_with_" (co-occurrence language); the CAVEATS footnote appears on all four sheets
  5. The Metadata sheet records DOI_ATTRIBUTION_WINDOW_DAYS = 90 and includes comparison counts for ±30-day and ±180-day windows as sensitivity context
**Plans**: TBD

### Phase 130: Registration, Smoke Test, and HiPerGator Runtime
**Goal**: R/111 is fully registered in the pipeline's discovery/validation infrastructure and the DoI layer's correctness is gated by a HiPerGator runtime pass on real DIAGNOSIS data
**Depends on**: Phase 129
**Requirements**: DOI-QA-01, DOI-QA-02, DOI-QA-03

**Design constraints:**
- R/39_run_all_investigations.R: R/111 added to investigation_scripts vector and doi_attribution_report.xlsx added to expected_xlsx list
- R/SCRIPT_INDEX.md: R/111 row added to Post-Renumber Investigations (100+) table
- R/88 new section [30/30]: 10+ checks — DOI_CODE_MAP existence, length >= 20, no-overlap with cancer maps (the critical hard-stop assertion), is_doi_code() / classify_doi_codes() functional spot-checks, utils_doi.R and R/111 file existence, doi_encounters.rds and doi_patients.rds existence and column validation, IS_LOCAL-gated HiPerGator runtime block that queries real DIAGNOSIS table and logs DoI hit counts
- HiPerGator runtime confirmation (real DIAGNOSIS table, logged DoI category counts) recorded in phase transition notes — this is the definition-of-done gate; structural-only pass is insufficient
- Dual-environment strategy: structural verify on Windows (grep/parse), runtime confirm on HiPerGator

**Success Criteria** (what must be TRUE):
  1. R/111_doi_attribution_report.R appears in R/39 investigation_scripts and expected_xlsx; doi_attribution_report.xlsx is listed in the expected outputs
  2. R/88 Section [30/30] passes with all 10+ checks green, including the no-overlap assertion between DOI_CODE_MAP keys and CANCER_SITE_MAP / ICD9_CANCER_SITE_MAP keys — zero tolerance for key collision
  3. HiPerGator runtime is confirmed: R/111 executes against the real DIAGNOSIS table, DoI category counts are logged (RA expected to dominate; NMO and pemphigus expected rare), and the confirmation is explicitly recorded in phase transition notes (not prose-only attestation)
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 127. Code-Set and Infrastructure | v3.3 | 1/2 | In Progress|  |
| 128. DoI Classification | v3.3 | 0/TBD | Not started | - |
| 129. Attribution Linkage and Output | v3.3 | 0/TBD | Not started | - |
| 130. Registration, Smoke Test, HiPerGator | v3.3 | 0/TBD | Not started | - |
