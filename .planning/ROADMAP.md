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
- ⏸️ **v3.3 Rituximab/Methotrexate-Associated Diagnoses of Interest** - Phases 127-131 (open, deferred alongside v3.4 pending HiPerGator verification)
- 🔄 **v3.4 R Pipeline Code Review Remediation** - Phases 132-136 (in progress)

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

### ⏸️ v3.3 Rituximab/Methotrexate-Associated Diagnoses of Interest (Open, deferred — see v3.4 below)

**Milestone Goal:** Identify the non-malignant diagnoses that rituximab and methotrexate treat (autoimmune, inflammatory, hematologic), add them as a new diagnosis-of-interest (DoI) class distinct from the cancer cascade, and use them to disambiguate treatment attribution — flagging when a patient's rituximab/MTX co-occurs with a non-lymphoma condition. The cancer cascade and all existing outputs are read-only throughout.

## Phases (v3.3)

- [x] **Phase 127: Code-Set and Infrastructure Centralization** (2 plans) - DOI_CODE_MAP + utils_doi.R + fixture augmentation (completed 2026-07-15)
- [x] **Phase 128: DoI Classification** (2 plans) - DuckDB DIAGNOSIS pull, classify, mutual-exclusivity hard-stop, cached artifacts (completed 2026-07-15)
- [x] **Phase 129: Attribution Linkage and Output** - Two-tier join, three-state flag, 4-sheet xlsx, HIPAA suppression (completed 2026-07-16)
- [ ] **Phase 130: Registration, Smoke Test, and HiPerGator Runtime** - R/39 + SCRIPT_INDEX + R/88 section + runtime gate
- [x] **Phase 131: All-Codes-Resolved MED_ADMIN/DISPENSING NDC Coverage + Medication Column** - Generalized NDC crosswalk detection across all RXNORM vectors, per-code Source Table tagging, normalized Medication column (completed 2026-07-22)

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
- [x] 127-02-PLAN.md — R/utils/utils_doi.R (is_doi_code DX_TYPE-gated + classify_doi_codes) + DIAGNOSIS fixture augmentation (ICD-10 M05.9, ICD-9 714.0) [DOI-CLASS-01, DOI-QA-04] (Wave 2, depends on 127-01)

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
**Plans**: 2 plans
- [x] 128-01-PLAN.md — R/111 setup + DuckDB-native prefix pushdown pull of DIAGNOSIS + classify + paraneoplastic_flag + in_hl_cohort + mutual-exclusivity hard-stop + doi_encounters.rds [DOI-CLASS-02/04/05] (Wave 1)
- [x] 128-02-PLAN.md — R/111 Section 7: patient-grain rollup + tabyl(doi_category) clinical-plausibility review + doi_patients.rds + close_pcornet_con [DOI-CLASS-03] (Wave 2, depends on 128-01)

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
**Plans**: 2 plans
- [x] 129-01-PLAN.md — Attribution engine: inputs load, dated HL pull, two-tier linkage, three-state flag, attribution_method (DOI-ATTR-01/02/03)
- [x] 129-02-PLAN.md — 4-sheet doi_attribution_report.xlsx: raw counts + internal-only note + CAVEATS footnote + +/-30/+/-180 sensitivity (DOI-OUT-01/02/03)

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
**Plans**: 2 plans
- [x] 130-01-PLAN.md — Register R/111 (classification) + R/112 (attribution) in R/39 (dependency order) + expected_xlsx; add two SCRIPT_INDEX.md rows + tally [DOI-QA-01] (Wave 1)
- [ ] 130-02-PLAN.md — R/88 Section 15w DoI validation (mutual-exclusivity hard-stop + IS_LOCAL-gated runtime) + SMOKE-130-01; HiPerGator runtime human-verify checkpoint with logged DoI counts [DOI-QA-02, DOI-QA-03] (Wave 1)

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 127. Code-Set and Infrastructure | v3.3 | 2/2 | Complete    | 2026-07-15 |
| 128. DoI Classification | v3.3 | 2/2 | Complete    | 2026-07-15 |
| 129. Attribution Linkage and Output | v3.3 | 2/2 | Complete    | 2026-07-16 |
| 130. Registration, Smoke Test, HiPerGator | v3.3 | 1/2 | In Progress|  |
| 131. All-Codes-Resolved MED_ADMIN/DISPENSING + Medication Column | 4/4 | Complete   | 2026-07-22 |  |

### Phase 131: Update all_codes_resolved.xlsx to include MED_ADMIN NDC-resolved codes and a normalized drug-name column

**Goal:** all_codes_resolved.xlsx (and its 5 per-type siblings) reflect true MED_ADMIN/DISPENSING NDC-resolved code coverage across all 4 RXNORM vector categories, with a per-code-accurate Source Table label and a normalized Medication column on every drug-relevant sheet
**Requirements**: MEDXLSX-01, MEDXLSX-02, MEDXLSX-03, MEDXLSX-04, MEDXLSX-05, MEDXLSX-06, MEDXLSX-07, SMOKE-131-01 (ad-hoc IDs -- this phase has no formal ROADMAP requirement entries in REQUIREMENTS.md; derived from CONTEXT.md's locked decisions per the discuss-phase discussion)
**Depends on:** Phase 130
**Plans:** 4/4 plans complete

**Design constraints:**
- Reuses get_chemo_hits() (Phase 122, R/utils/utils_treatment.R) generalized across chemo_rxnorm/sct_rxnorm/immunotherapy_rxnorm/supportive_care_rxnorm via an additive return_source parameter -- zero behavior change for its 5 existing callers (R/10, R/11, R/25, R/26, R/76)
- Records/Patients counts deduplicated on (ID, treatment_date, triggering_code) to avoid inflating counts when the same administration is reachable via multiple source paths (RX+ND, or PRESCRIBING+MED_ADMIN)
- MEDICATION_LOOKUP (Phase 114) extended to consult Phase 120's orphaned Supportive Care "Normalized Meaning" col G when materialized, falling back gracefully to column 3 today (col G not yet written in this repo's copy of the reference Excel -- R/105 has not executed against real data yet)
- New fallback_normalize_medication() heuristic (adapted from Phase 120's rule_based_ingredient()) covers RxNorm-STR salt/dose stripping, HCPCS J-code "Injection, X, dose" stripping, and unchanged multi-ingredient (" / "-delimited) passthrough
- Medication column added to Chemotherapy/Supportive Care/Immunotherapy/SCT (SCT gated to Code Type == RXNORM rows only); explicitly excluded from Radiation
- Both write_resolved_xlsx() (per-type files) and the combined-workbook per-category loop share one resolved_xlsx_layout() helper so they cannot silently diverge

**Success Criteria** (what must be TRUE):
  1. Codes only detectable via MED_ADMIN NDC-type or DISPENSING now appear with non-zero record/patient counts, across all 4 RXNORM vector categories (not chemo-only)
  2. The Source Table column distinguishes MED_ADMIN (RX) / MED_ADMIN (NDC) / DISPENSING (NDC) / PRESCRIBING per code, replacing the old static per-vector label
  3. Chemotherapy, Supportive Care, Immunotherapy, and SCT sheets each show a populated Medication column (never blank for a code that should have one); SCT shows Medication only for RXNORM rows; Radiation has no Medication column at all
  4. Records/Patients counts are not inflated by double-counting administrations reachable via multiple source paths
  5. R/88 Section 15x validates all of the above structurally, with a SMOKE-131-01 summary line
**Plans**: 4 plans
- [x] 131-01-PLAN.md -- MEDICATION_LOOKUP Supportive Care col G wiring + fallback_normalize_medication() heuristic normalizer (R/00_config.R) [MEDXLSX-01, MEDXLSX-02] (Wave 1)
- [x] 131-02-PLAN.md -- get_chemo_hits() additive return_source tagging + R/50 Section 3/4 MED_ADMIN/DISPENSING NDC generalization across all 4 RXNORM vectors with dedup [MEDXLSX-03, MEDXLSX-04, MEDXLSX-05] (Wave 1)
- [x] 131-03-PLAN.md -- Medication column population (Section 4) + shared xlsx-writer layout across write_resolved_xlsx() and the combined workbook (Section 6) [MEDXLSX-06, MEDXLSX-07] (Wave 2, depends on 131-01 + 131-02)
- [x] 131-04-PLAN.md -- R/88 Section 15x structural smoke-test validation + SMOKE-131-01 summary line [SMOKE-131-01] (Wave 3, depends on 131-01/02/03)

### 🔄 v3.4 R Pipeline Code Review Remediation (Active)

**Milestone Goal:** Fix the crash-causing and wrong-published-number defects surfaced by the 2026-07-23 full-pipeline code review, and standardize the 8 recurring cross-cutting bug patterns (record-vs-patient-count confusion, code-normalization drift, can't-fail tests, etc.) at the shared-helper layer so they stop recurring script-by-script. Source: `R_pipeline_code_review.md`.

**Phase sequencing rationale:** Phases follow the review's own "Suggested fix order" (its 5 numbered stages), used as the primary phase-sequencing signal per REQUIREMENTS.md's locked scope: (1) unblock the crashers, (2) fix wrong published numbers, (3) harden the ingest gate + make tests honest, (4) standardize the 8 cross-cutting patterns once at the shared-helper layer, (5) confirm the two flagged loose ends. `DOCS-01` (the empty reference manual, critical/high finding #7) and `DATA-07` (finding #8) are folded into stage 2's phase since the review's own critical/high findings table lists them adjacent to the other "wrong output" findings without a separate stage, and splitting them into their own single-requirement phases would violate this milestone's coarse granularity.

## Phases (v3.4)

- [x] **Phase 132: Crash Fixes** - Unblock 6 scripts (`74`,`81`-`85`) that abort immediately on editor artifacts
 (completed 2026-07-25)
- [x] **Phase 133: Critical Correctness Fixes** - Fix wrong published numbers (SCT filter, total_records, HL anchor date, same-week desync, age_at_episode) + the content-empty reference manual (completed 2026-07-25)
- [x] **Phase 134: Ingest Integrity and Honest Tests** - Harden the DuckDB ingest promotion gate + fix 5 can't-fail validators (completed 2026-07-25)
- [x] **Phase 135: Shared-Helper Standardization** - Standardize 7 cross-cutting patterns (A, B, C, D, F, G, H) once at the shared-helper layer (completed 2026-07-25)
- [x] **Phase 136: Confirm Loose Ends** - Locate `suppress_small`/`clean_multi_value`/`union_field`; reconcile `date_range_max` vs. the extract cutoff (completed 2026-07-25)

## Phase Details (v3.4)

### Phase 132: Crash Fixes
**Goal**: The six scripts that currently abort immediately on an editor artifact run past that point and execute their intended logic
**Depends on**: Phase 131 (v3.4 starting point; independent of v3.3's open work)
**Requirements**: CRASH-01, CRASH-02

**Design constraints:**
- Stray bare `n` line appears immediately after `source("R/00_config.R")` in `R/74`, `R/81`, `R/82`, `R/83`, `R/84`, `R/85` (three separate occurrences within `84`/`85`) — delete each occurrence outright, don't comment it out
- `R/84`'s triggered branch calls unqualified `walk()` with no `library(purrr)` attached — align with `R/85`'s correct `purrr::walk()` usage (either qualify the call or attach purrr)
- These are one-character/one-line fixes per the review; verification is that each script no longer throws `object 'n' not found` or `could not find function "walk"` at the point it previously crashed

**Success Criteria** (what must be TRUE):
  1. `R/74`, `R/81`, `R/82`, `R/83`, `R/84`, `R/85` no longer abort with `object 'n' not found` immediately after sourcing `R/00_config.R`
  2. `R/84`'s previously-crashing branch resolves its `walk()` call via `purrr::walk()` (or an attached `library(purrr)`) without `could not find function "walk"`
  3. Each of the six scripts proceeds past its former abort point to execute its intended logic instead of halting on the editor artifact
**Plans**: 4 plans
- [x] 132-01-PLAN.md -- Remove stray bare `n` from R/74, R/81, R/82, R/83 (1 occurrence each) [CRASH-01] (Wave 1)
- [x] 132-02-PLAN.md -- Remove 3 stray bare `n` occurrences from R/84 + attach library(purrr) to fix walk() crash [CRASH-01, CRASH-02] (Wave 1)
- [x] 132-03-PLAN.md -- Remove 3 stray bare `n` occurrences from R/85 (purrr::walk() calls untouched) [CRASH-01] (Wave 1)
- [x] 132-04-PLAN.md -- R/88 Section 15y structural regression-guard checks for CRASH-01/CRASH-02 [CRASH-01, CRASH-02] (Wave 2, depends on 132-01/02/03)

### Phase 133: Critical Correctness Fixes
**Goal**: The pipeline's published numbers and generated reference manual are correct — no analytic output is silently wrong or inert, and the documentation generator produces real content
**Depends on**: Phase 132
**Requirements**: DATA-01, DATA-02, DATA-03, DATA-04, DATA-05, DATA-06, DATA-07, DOCS-01

**Design constraints:**
- `R/28`: `treatment_type == "Stem Cell Transplant"` changes to `treatment_type == "SCT"` to match the value used everywhere else in the pipeline
- `R/46`: `total_records` must collapse to distinct code-level counts (e.g. aggregate `dx_record_counts` by category directly) instead of joining per-code counts onto the patient-grain frame before `sum()`
- `R/47`: `first_hl_dx_date` must filter `DX_DATE >= 1910-01-01` (the same `SENTINEL_CUTOFF` used by `48`/`49`) **before** `min()`, removing the post-hoc `== 1900` nullify
- `R/48` must exclude HL anchor codes (C81 + 201.x) from its post-HL "second cancer" set, matching `R/49`'s existing exclusion — both scripts inherit the corrected `R/47` anchor date
- `R/49`'s category/total `both_count` must reflect the true pre∩post **patient** intersection at category grain, not a per-code sum, so `pre + post − both` reconciles
- `R/67`→`R/68` and `R/95`→`R/96`: after `pmin`/`pmax` reorders `source_1`/`source_2`, `admit_date_1`/`admit_date_2` must be swapped as a bound unit (or the two `(date, source)` tuples grouped without breaking their correspondence) so the downstream `(ID, date, source)` join back to ENCOUNTER stays correct
- `R/89`'s `parse_script_header()` must anchor `header_end` to the field block's closing bar (3rd `===` bar / first non-comment line), not the 2nd bar
- `R/101`: `age_at_episode` must be computed **before** `episode_start` is reassigned to the group's `min()`, or indexed against a separately-named min column, so it reflects the row at the group's earliest `episode_start`

**Success Criteria** (what must be TRUE):
  1. `R/28`'s `sct_dates`, `is_sct_conditioning_context`, and `days_to_nearest_sct` are populated for patients with `treatment_type == "SCT"` instead of permanently empty/FALSE/NA
  2. `R/46`'s `total_records` (including the TOTAL row) reflects true code-level record counts, not per-code records multiplied by patient count
  3. `R/47`'s `first_hl_dx_date` retains a patient's true HL anchor date when both a real date and a sentinel are present; `R/48` excludes HL anchor codes from its post-HL "second cancer" set; `R/49`'s `both_count` reconciles at category grain (`pre + post − both`)
  4. `R/68` and `R/96`'s same-week detail files keep each `(admit_date, source)` pair correctly bound after the `pmin`/`pmax` reordering, so the downstream ENCOUNTER join no longer misclassifies pairs into Distinct/Partial or undercounts near-duplicates
  5. `R/89`'s generated reference manual captures each script's actual Purpose/Inputs/Outputs/Dependencies/Requirements text instead of "Not documented"; `R/101`'s `age_at_episode` reflects the row at each group's earliest `episode_start`
**Plans**: 1 plan
- [x] 133-01-PLAN.md -- All 8 correctness fixes (R/28, R/46, R/47, R/48, R/49, R/67, R/68, R/95, R/96, R/89, R/101) [DATA-01..07, DOCS-01] (Wave 1)

### Phase 134: Ingest Integrity and Honest Tests
**Goal**: A "passing" DuckDB ingest and a "passing" test/validator run are both strong evidence again — neither can silently succeed while the thing they check is actually broken
**Depends on**: Phase 133
**Requirements**: INGEST-01, PATTERN-E

**Design constraints:**
- `R/03`: `stop()` on any table write failure before the atomic swap (discard the `.tmp` database); assert `setequal(ingested, expected)` before promotion; summary reports real per-table pass/fail counts, not a hardcoded `"N/N passed"`
- `R/81`: remove/adjust `coerce_types()` so it no longer normalizes DuckDB vs. RDS types before `waldo::compare()` — real type divergence must be visible
- `R/82`/`R/83`: the "≥3× speedup on 3 of 5 scripts" check must actually benchmark all 5 scripts, not just 1
- `R/88`: separate skip counters from pass counters in the summary tally; invert the `cause_of_death` "drop" check so it fails when the value is genuinely absent (not when present)
- `R/96_validate_payer_dt`: the FLM-override fixture must start from a non-Medicaid state so the override is provably exercised
- `R/98_validate_r28_migration`: compare against an independently-generated baseline, not a copy of its own output

**Success Criteria** (what must be TRUE):
  1. `R/03` aborts via `stop()` and discards the `.tmp` database when any table fails to write, asserts `setequal(ingested, expected)` before promoting, and its summary reports the real per-table pass/fail counts
  2. `R/81` no longer coerces types before `waldo::compare()`, so genuine type divergence between DuckDB and RDS outputs is detectable
  3. `R/82`/`R/83`'s speedup check benchmarks all 5 scripts (not 1) before evaluating the "≥3× on 3 of 5" claim; `R/88` separates skip counts from pass counts and its `cause_of_death` check fails when the value is genuinely absent
  4. `R/96_validate_payer_dt`'s FLM-override fixture starts from a non-Medicaid state so the override path is provably exercised; `R/98_validate_r28_migration` compares against an independently-generated baseline instead of a copy of its own output
**Plans**: TBD

### Phase 135: Shared-Helper Standardization
**Goal**: The 7 recurring cross-cutting bug patterns still in scope are fixed once at the shared-helper layer, so they stop recurring script-by-script
**Depends on**: Phase 134
**Requirements**: PATTERN-A, PATTERN-B, PATTERN-C, PATTERN-D, PATTERN-F, PATTERN-G, PATTERN-H

**Design constraints:**
- PATTERN-A: de-duplicate to `n_distinct(ID)` / distinct code before totaling in `R/23`, `R/33` (CODE-03), `R/43`/`R/44` (TOTAL rows), `R/50` (grand total), `R/91`, `R/100` (Sheet 1) — `R/46`'s instance is already covered by DATA-02 in Phase 133, not re-touched here
- PATTERN-B: one shared code-normalization convention (strip **all** dots + `toupper()` + dotted/undotted union) applied consistently to `R/13_survivorship_encounters.R`, `R/42_build_code_descriptions.R`, `utils_cancer.R` (`classify_codes`/`is_cancer_code`), and `utils_doi.R` (`classify_doi_codes()`)
- PATTERN-C: replace the over-inclusive `^[CD]` with `is_cancer_code()` (or `"^C|^D[0-4]"`) in `R/40`, `R/43`, `R/44`, `R/46`
- PATTERN-D: classify transient (429/503/504/timeout/500/502) vs. permanent "not found" errors in `R/21_investigate_unmatched.R` (currently no retry at all), `R/27`, `R/105`, `R/108`; retry transient errors; never persist a transient failure as a permanent cache miss / dropped crosswalk entry
- PATTERN-F: harden in-place `R/00_config.R` rewriting in `R/21`, `R/22`, `R/50`, `R/98` (regex/quote-handling) so newly-discovered codes are never silently dropped on a parse/write failure — a full move to a data-driven config source is explicitly out of scope for this milestone (see REQUIREMENTS.md Out of Scope) unless the hardened guard proves insufficient
- PATTERN-G: add a death-before-birth check to `R/53_death_date_validation.R`; apply NA-safe `min_or_na`/`max_or_na` guards consistently in `R/14`, `R/31`, `R/93`
- PATTERN-H: rename or re-aggregate `R/56`'s `encounter_count` (actually episode count), `R/57_explore_dx_deduplication`'s same mislabel, `R/62`'s `date_tier_detail` (patient×type×episode×date grain, not one-row-per-patient-per-date), and `R/67`'s `n_total_encounters` (double-counts dates used in both roles)

**Success Criteria** (what must be TRUE):
  1. Record/patient totals in `R/23`, `R/33`, `R/43`/`R/44`, `R/50`, `R/91`, `R/100` are computed by de-duplicating to the intended grain before totaling
  2. A single shared code-normalization convention (strip all dots + `toupper` + dotted/undotted union) is applied consistently across `R/13`, `R/42`, `utils_cancer.R`, and `utils_doi.R`
  3. Neoplasm filters in `R/40`, `R/43`, `R/44`, `R/46` use `is_cancer_code()` (or `^C|^D[0-4]`) instead of the over-inclusive `^[CD]`
  4. External-API calls in `R/21`, `R/27`, `R/105`, `R/108` classify transient errors separately from genuine "not found," retry transient errors, and never persist a transient failure as a permanent miss
  5. In-place `R/00_config.R` rewriting in `R/21`, `R/22`, `R/50`, `R/98` is hardened so newly-discovered codes are never silently dropped; `R/53` gets a death-before-birth guard and `R/14`/`R/31`/`R/93` use NA-safe `min_or_na`/`max_or_na` consistently; `R/56`, `R/57_explore_dx_deduplication`, `R/62`, and `R/67`'s grain-mislabeled columns are renamed or re-aggregated to match their documented grain
**Plans**: TBD

### Phase 136: Confirm Loose Ends
**Goal**: The review's two flagged unknowns are resolved with a documented answer, not left as open questions
**Depends on**: Phase 135
**Requirements**: CONFIRM-01, CONFIRM-02

**Design constraints:**
- `suppress_small()`/`clean_multi_value()`/`union_field()` were not found in any of the 14 `utils_*.R` modules during the review; `clean_multi_value` is referenced as "reused from R/52" — locate the actual definitions (likely `R/00_config.R` or inline in a script) and confirm they load correctly in every consumer
- `CONFIG$analysis$date_range_max` (2025-03-31) vs. the actual extract cutoff (20250915) — determine whether valid Apr-Sep 2025 encounters/deaths are currently flagged out-of-range and dropped by `R/01`'s date validation, and correct the bound if so

**Success Criteria** (what must be TRUE):
  1. The actual file/line definitions of `suppress_small()`, `clean_multi_value()`, and `union_field()` are located and documented; each is confirmed to load correctly in every script/module that calls it
  2. `CONFIG$analysis$date_range_max` is reconciled against the 20250915 extract cutoff, with an explicit finding on whether Apr-Sep 2025 encounters/deaths were being dropped
  3. If criterion 2 finds real data being dropped, `R/01`'s date validation bound is corrected; if not, the finding documents why 2025-03-31 is intentional and no data is lost
**Plans**: TBD

### Phase 137: ZIP9 Temporal Assignment
**Goal**: A shared utility `get_zip9_at_date()` exists that resolves any patient's ZIP9/ZIP5 at any query date using interval overlap with a most-recent-before fallback — ready for consumption by future SES-index phases without duplicated logic
**Depends on**: Phase 136 (independent; addresses ZIP/address domain, not the code-review remediation chain)
**Requirements**: (none mapped in REQUIREMENTS.md — new capability phase)

**Design constraints:**
- get_zip9_at_date(ids, dates) in R/utils/utils_address.R — pure-function module, no side effects, auto-loaded by R/00_config.R
- Primary rule: ADDRESS_PERIOD_START <= date < ADDRESS_PERIOD_END; NA ADDRESS_PERIOD_END treated as open-ended (coerced to 9999-12-31)
- Fallback: most-recent ADDRESS_PERIOD_START on or before date; no match → NA for ZIP9 and ZIP5
- Returns 5-column tibble: ID, query_date, ZIP9, ZIP5, match_type ("interval" / "most_recent_before" / "none")
- R/114 uses probe-first gate for both LDS_ADDRESS_HISTORY CSV and the existing zip_change_frequency.xlsx before doing any work
- R/114 appends via wb_load() (never wb_workbook()) to preserve R/106's existing sheets
- ZIP normalization helpers (normalize_zip9, normalize_zip5, normalize_zip5_raw) copied verbatim from R/106 — not duplicated from scratch

**Success Criteria** (what must be TRUE):
  1. R/utils/utils_address.R defines get_zip9_at_date(), normalize_zip9(), normalize_zip5(), normalize_zip5_raw() with no side effects
  2. get_zip9_at_date() correctly classifies interval matches, most-recent-before fallbacks, and no-match rows; NA ADDRESS_PERIOD_END rows are included in interval matching
  3. R/114_zip9_temporal_lookup.R validates the function with a sample call and appends "Address Timeline Diagnostics" sheet to output/zip_change_frequency.xlsx without overwriting R/106's existing sheets
  4. R/88 Section 15ab passes all structural checks (artifact existence, function definitions, wb_load anti-pattern guard, R/39 registration, SCRIPT_INDEX entries)
**Plans**: 2 plans
- [x] 137-01-PLAN.md — R/utils/utils_address.R: normalize_zip9/zip5/zip5_raw + get_zip9_at_date() temporal lookup (Wave 1)
- [x] 137-02-PLAN.md — R/114_zip9_temporal_lookup.R + R/39 registration + R/88 Section 15ab + R/SCRIPT_INDEX.md update (Wave 2, depends on 137-01)

## Progress (v3.4)

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 132. Crash Fixes | v3.4 | 4/4 | Complete    | 2026-07-25 |
| 133. Critical Correctness Fixes | v3.4 | 1/1 | Complete    | 2026-07-25 |
| 134. Ingest Integrity and Honest Tests | v3.4 | TBD | Complete    | 2026-07-25 |
| 135. Shared-Helper Standardization | v3.4 | 5/7 | Complete    | 2026-07-25 |
| 136. Confirm Loose Ends | v3.4 | 2/2 | Complete    | 2026-07-25 |
| 137. ZIP9 Temporal Assignment | standalone | 2/2 | Complete    | 2026-07-25 |

### Phase 138: resolve log2.txt problems

**Goal:** Fix the 3 root-cause bugs behind the 9 script failures in log2.txt (real HiPerGator R/39 run): DuckDB gsub-in-lazy-filter in R/13, `tables_ingested <<-` scoping bug in R/03, and PATID column rename in R/53. Cascading failures (R/70, R/71, R/72, R/52, R/101, R/104) resolve automatically.
**Requirements**: D-01 through D-09
**Depends on:** Phase 137
**Plans:** 5/5 plans complete

Plans:
- [x] 138-01-PLAN.md — Fix R/13 DuckDB gsub-in-lazy-filter: pre-compute combined dotted+undotted IN-list (D-01, D-02, D-03) (Wave 1)
- [x] 138-02-PLAN.md — Fix R/03 `tables_ingested <<-` scoping bug: change to `<-` (D-04, D-05) (Wave 1)
- [x] 138-03-PLAN.md — Fix R/53 `select(ID = PATID, ...)` PATID column bug: change to `select(ID, ...)` (D-06, D-07) (Wave 1)
- [x] 138-04-PLAN.md — R/88 Section 15ac: 3 static grep assertions for each fix + SMOKE-138-01 footer (D-08, D-09) (Wave 2, depends on 138-01/02/03)
