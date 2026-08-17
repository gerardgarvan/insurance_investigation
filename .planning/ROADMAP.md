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

### Phase 139: ZIP Stability & Imputation Occurrence Counts

**Goal:** A counting-and-validation deliverable (R/115_zip_stability_counts.R) that measures how often patients' 9-digit and 5-digit ZIP codes actually change (Part A, including a carry-forward validation curve), counts how often each imputation scenario S1-S4 from the 08/04 team notes would fire (Part B, ordered + unordered, encounter + patient level, direction-split), and reports a cumulative completeness waterfall reconciled against the notes' 26-patient control total (Part C) — to inform, not decide, the team's carry-forward time-window and ADI-vs-SDI design choices. This phase measures; it does not modify `get_zip9_at_date()` or build `approximate_zip9()`.
**Requirements**: none mapped in REQUIREMENTS.md (standalone investigation deliverable) — plans use CONTEXT.md decision IDs (A-01..A-06, B-01..B-04, C-01..C-02) as acceptance criteria instead
**Depends on:** Phase 138 (independent; addresses ZIP/address domain like Phase 137, not the code-review remediation chain)
**Plans:** 4/4 plans complete

**Design constraints:**
- The source notes (139-CONTEXT.md) assumed a prior "zip9-approximation" phase had shipped `approximate_zip9()`, `is_sentinel_zip5()`, and an "AMEND-01" ZIP5-coalesce fix — none of that exists. Resolution: `approximate_zip9()` is not needed (Part B/C count occurrences, they do not write imputed values); `is_sentinel_zip5()` is added as a small new sibling function in `R/utils/utils_address.R` (Plan 01); the ZIP5-coalescing logic is applied locally inside R/115 (mirroring R/106's already-proven raw-column-preferred-with-derived-fallback pattern), not inside `utils_address.R` — `get_zip9_at_date()` itself is never modified (Out of Scope, honored)
- Part A is computed on the LDS_ADDRESS_HISTORY universe; Part B and C are computed on the ENCOUNTER universe (Pitfall 1) — stated explicitly in every sheet header, never mixed
- A-06's carry-forward validation curve (not in the source notes, added as a recommended analysis) runs as a leave-one-out hold-out test on address-history spells, binned by gap-days, at exact-ZIP9 and same-ZIP5 accuracy tiers; a block-group tier is attempted only if a Neighborhood Atlas crosswalk file is found (none exists in this repo currently) and degrades gracefully otherwise
- B's S1→S2→S3 ordered scenario assignment plus unordered eligible-for counts plus backward/forward/either direction split (S1, S2 only — S3 stays backward-only per its own definition) are all reported so the numbers reconcile against each other; S3 is counted but explicitly flagged as unresolved (still pending as of 08/04 notes), never presented as a decided resolution
- C-02's reconciliation against the notes' "only 26 patients with no 5-digit ZIP code at any single point" is computed from the full address-history universe (not encounter-level scenario logic) and produces a loud, unmissable warning — in console AND as a flagged QC-sheet cell in the xlsx itself — if it fails to reconcile within tolerance, since CONTEXT.md calls this "the single most useful validation in the phase"
- Deliverable is a single 8-sheet styled xlsx (`output/zip_stability_counts_YYYYMMDD.xlsx`, KEY sheet leftmost) using UF colors (#0021A5, #FA4616); registered in R/39's `investigation_scripts` (not `expected_xlsx`, matching R/106's own precedent for a dated-filename output) and validated structurally by a new R/88 section

**Success Criteria** (what must be TRUE):
  1. `is_sentinel_zip5()` exists in `R/utils/utils_address.R`; `get_zip9_at_date()` is unmodified
  2. `R/115_zip_stability_counts.R` computes Part A per-patient ZIP9/ZIP5 stability metrics (distinct counts, transitions, plus4-only transitions, exposure-denominator rate, gap-time distribution) and the A-06 carry-forward validation curve
  3. `R/115` computes Part B's S1-S4 imputation-scenario occurrence counts (ordered + unordered, encounter + patient level, backward/forward/either direction split) from the real ENCOUNTER table
  4. `R/115` computes Part C's completeness waterfall and the C-02 26-patient reconciliation, with a visible, unmissable flag if reconciliation fails
  5. `output/zip_stability_counts_YYYYMMDD.xlsx` is produced with all 8 sheets; R/115 is registered in R/39, R/88 (new structural-checks section), and R/SCRIPT_INDEX.md
**Plans**: 4 plans
- [x] 139-01-PLAN.md — `is_sentinel_zip5()` utility + R/115 setup/probe-gate/ZIP5-coalescing address load + Part A-01/A-02/A-03/A-04/A-05 per-patient stability metrics [A-01, A-02, A-03, A-04, A-05] (Wave 1)
- [x] 139-02-PLAN.md — Part A-06 carry-forward leave-one-out validation curve, gap-binned, exact-ZIP9/same-ZIP5/block-group tiers [A-06] (Wave 2, depends on 139-01)
- [x] 139-03-PLAN.md — Part B: ENCOUNTER pull + S1-S4 ordered/unordered scenario counts + backward/forward/either direction split [B-01, B-02, B-03, B-04] (Wave 3, depends on 139-01, 139-02)
- [x] 139-04-PLAN.md — Part C completeness waterfall + C-02 26-patient reconciliation + QC sheet + full 8-sheet xlsx assembly + R/39/R/88/SCRIPT_INDEX registration [C-01, C-02] (Wave 4, depends on 139-01, 139-02, 139-03)

### Phase 140: Resolve C-02 reconciliation gate and finalize ZIP assignment design (ZIP5 unit, uncapped carry-forward, backward-only primary spec) for zip_stability_counts workbook

**Goal:** Phase 139's `zip_stability_counts_20260806.xlsx` is unblocked for release: the C-02 reconciliation gate failure (computed 665 vs. expected 26) is resolved via an explicit, recorded team decision rather than a silently-widened tolerance; the coverage gaps behind it are classified and reported; ZIP5-vs-ZIP9 as the analysis unit, uncapped carry-forward with a gap-days covariate, and backward-only-primary/forward-inclusive-sensitivity scenario reporting are all implemented and confirmed by explicit team decisions (D-1..D-4) rather than silently assumed.
**Requirements**: none mapped in REQUIREMENTS.md (standalone remediation/investigation deliverable) — plans use 140-CONTEXT.md's own task/decision IDs (P-01a..P-07c, D-1..D-4) as acceptance criteria instead
**Depends on:** Phase 139 (resolves its C-02 gate failure on the real HiPerGator run)
**Plans:** 8/8 plans complete

**Design constraints:**
- 656 of the 665 C-02 gap (98.6%) are cohort patients with ZERO rows in `addr_coal` at all (a coverage question); only 9 are cohort patients present in `addr_coal` with no usable ZIP5 (the only population a genuine coalescing defect could produce) — the working hypothesis is that the team's "26" control total is stale relative to the now-correctly-cohort-scoped denominator, not a pipeline defect; `C02_TOLERANCE` (5L) is never widened to absorb this gap regardless of how D-1 resolves
- D-1 through D-4 (Owner: Erin/Amy) are team decisions the executing agent cannot unilaterally resolve — each is implemented as a `checkpoint:decision` task presenting the evidence and recording the team's answer, not silently assumed; P-01a (locating the originating 26-patient control total's denominator) and P-03a (obtaining the Neighborhood Atlas block-group crosswalk) additionally require human action Claude cannot automate (no record of the exact denominator exists in this repo; no CLI/API for the restricted crosswalk dataset)
- S1 is folded into S3 universally in the ordered scenario assignment (no longer a distinct bucket); a backward-only ordered waterfall is computed independently (its own case_when, never derived by summing `B_direction_split` rows) and reported as parallel columns alongside the existing forward-inclusive waterfall
- ZIP5 carried forward with NO hard time-window cap; `gap_days_at_assignment` (signed: positive = backward, negative = forward inference) is written into the analytic dataset as a covariate instead of a discard rule
- A second, encounter-anchored validation curve (sampling real `ADMIT_DATE`s) is added alongside A-06's existing record-anchored curve, which is explicitly relabeled a LOWER BOUND everywhere it appears (record-anchored sampling over-represents recently-changed addresses and structurally excludes single-record/most-stable patients)
- Out of scope: changes to `normalize_zip9()`/`normalize_zip5()`/`normalize_zip5_raw()`; caching `LDS_ADDRESS_HISTORY`; releasing the current-form `zip_stability_counts_20260806.xlsx`; building the P-06d forward-lookup production utility unless D-4 explicitly selects it (scoped as a follow-up plan, not built here)

**Success Criteria** (what must be TRUE):
  1. The 665-vs-26 C-02 gap is broken down by the script itself (cohort-absent-from-addr_coal vs. present-but-no-usable-ZIP5), and the original 26-patient denominator is either confirmed (with `C02_EXPECTED` reset and a documented basis) or explicitly recorded as unresolved (D-1) — never silently assumed either way
  2. Unparseable-date failure modes and the 280-patient filter-loss gap are classified/reported by the script, with any parser-extension decision (P-02b) explicitly flagged as pending real-data review
  3. The block-group crosswalk staging contract is fully documented (no code changes needed to activate it) and its acquisition is logged as a human action; ZIP5-as-analysis-unit (D-2) is an explicit recorded decision
  4. S1 is folded into S3 in the ordered assignment; a backward-only ordered waterfall is computed independently and reported as parallel columns on `C_completeness`; whether forward lookup becomes primary (D-4) is an explicit recorded decision
  5. `gap_days_at_assignment` exists as a signed per-encounter covariate (uncapped carry-forward, D-3 recorded); a second encounter-anchored validation curve exists alongside A-06, which is explicitly labeled a lower bound; Part A's universe difference from Part B/C is documented and self-checking
**Plans**: 8 plans (140-09 inserted as Wave 2a by 140-09-PATCH)
- [x] 140-01-PLAN.md — C-02 present-vs-absent breakdown (n_present_no_usable_zip5) + D-1 blocking decision on the 26-patient denominator + C02_EXPECTED/KEY-sheet resolution [P-01a, P-01b, P-01c, D-1] (Wave 1) — D-1 resolved as a comparison-basis correction (n_present_no_usable_zip5 vs C02_EXPECTED, not either anticipated option-a/option-b branch); C02_EXPECTED/C02_TOLERANCE unchanged, gate remains a documented, open FAIL pending team follow-up on the original 26's provenance
- [x] 140-02-PLAN.md — Block-group crosswalk staging contract (data/reference/README.md) + human-action acquisition checkpoint + D-2 ZIP5-as-analysis-unit decision [P-03a, P-03b, P-03c, D-2] (Wave 1) — crosswalk acquisition deferred (not available); D-2 resolved option-a (ZIP5 accepted now)
- [x] 140-09-PLAN.md — Retire unverifiable C-02_EXPECTED=26 control total as a gate input; rewire `c02_reconciled` onto two internally-checkable invariants (C-02a monotonicity via `compute_c02_baseline()`, C-02b partition identity) + D-5 coverage-floor decision [P-01d, P-01e, D-5] (Wave 2a, depends on 140-01) — inserted by 140-09-PATCH ahead of 140-03; D-5 resolved option-c ("no floor -- report only"); confirmed on real HiPerGator data 2026-08-08 via 140-03 Task 3 (both invariants PASS)
- [x] 140-03-PLAN.md — classify_unparseable_dates() + SECTION 3 wiring + explicit 280-patient filter-loss QC row [P-02a, P-02b, P-02c] (Wave 2b, depends on 140-01, 140-09) — real HiPerGator run confirmed 2026-08-08: all figures matched assumptions (656 vs 9 for C-02, 92.9% coverage, 4,912 unparseable dates, 280-patient filter loss); testthat 35/35 pass; P-02b resolved "genuinely unparseable, no parser gap" (100% of unparseable dates are blank_or_null); Wave 2.5 gate (140-08-PATCH FIX-14) passed, Wave 3 unblocked
- [x] 140-04-PLAN.md — assign_scenarios() dual-mode (S1 folded into S3, conditional on D-2 = option-a) + independent backward-only ordered waterfall parallel columns + D-4 forward-lookup-as-primary decision [P-06a, P-06b, P-06c, P-06d, D-2, D-4] (Wave 3, depends on 140-01, 140-02, 140-03) — D-4 resolved 2026-08-08 as option-a (backward-only PRIMARY, forward-inclusive SENSITIVITY-only, matching 140-CONTEXT.md's own recommendation); P-06d explicitly not triggered/not built (out of scope, `R/utils/utils_address.R` untouched)
- [x] 140-05-PLAN.md — gap_days_at_assignment signed covariate + non-monotonicity diagnostic (median_gap_within_bin) + D-3 uncapped-carry-forward decision [P-04a, P-04b, D-3] (Wave 4, depends on 140-04) — D-3 resolved 2026-08-10 as option-a (uncapped carry-forward accepted, gap covariates serve as analytic/sensitivity variables; already implemented by Task 1, no code changes required); option-b (capped at team-specified N) not selected/not built
- [x] 140-06-PLAN.md — build_encounter_anchored_validation_cases() (second estimate) + A-06 lower-bound relabeling [P-05a, P-05b] (Wave 5, depends on 140-05) — encounter-anchored curve (9th workbook sheet) added; A-06's record-anchored curve and both curves' own selection limitations explicitly labeled in the KEY sheet and each sheet's own subtitle; no checkpoint encountered
- [x] 140-07-PLAN.md — Part A universe-difference documentation (self-checking) + sentinel-nulling close-out + optional get_zip9_at_date() addr_full test seam [P-07a, P-07b, P-07c] (Wave 6, depends on 140-06) — universe cross-check relocated to SECTION 12 (n_distinct() both sides, 140-08-PATCH FIX-07); KEY sheet + all 4 Part A sheet subtitles carry an explicit universe note; sentinel-nulling documented reviewed-and-closed; get_zip9_at_date() gains an additive addr_full=NULL test seam (140-08-PATCH FIX-10) with a new dedicated test-utils-address.R; normalize_*()/is_sentinel_zip5() confirmed byte-for-byte unchanged. This was the final plan in Phase 140 (8/8) — all 24 of 140-CONTEXT.md's task/decision IDs addressed; phase-level goal verification (real HiPerGator run) still pending

### Phase 141: CONTEXT-zip9-imputation

**Goal:** Wire approximate_zip9() into R/115 and re-issue the xlsx workbook with imputation QC rows (D-01 through D-04).
**Requirements**: D-01, D-02, D-03, D-04
**Depends on:** Phase 140
**Plans:** 1/1 plans complete

Plans:
- [x] 141-01-PLAN.md — Wire approximate_zip9() into R/115: SECTION 11B (get_zip9_at_date |> approximate_zip9, RDS write, join onto encounter_zip), SECTION 13 imputation QC rows (8-level zip9_source breakdown + summary rows), SECTION 12 reviewer note, fixture tests. HiPerGator re-run confirmed 2026-08-13: 76.5% post-imputation coverage, 42,651 encounters gained via carry-forward, 0 via zip5_modal, c02_reconciled PASS. [D-01, D-02, D-03, D-04]

### Phase 142: 180-Day Treatment Episodes + Drug-Name Deduplication

**Goal:** Produce 180-day Gantt CSVs (gantt_episodes_180.csv, gantt_detail_180.csv) with the same schema as the 90-day files, and fix drug-name deduplication so salt variants like "Vinblastine Sulfate" collapse to the canonical name
**Requirements**: EP-DEDUP-01, EP-180-01, EP-180-02
**Depends on:** Phase 141
**Plans:** 2 plans

Plans:
- [ ] 142-01-PLAN.md — Add vinblastine sulfate alias to DRUG_NAME_ALIASES in R/00_config.R; audit bleomycin, vincristine, dacarbazine salt variants [EP-DEDUP-01] (Wave 1)
- [ ] 142-02-PLAN.md — Extend R/26 to produce treatment_episodes_180.rds + treatment_episode_detail_180.rds (Section 5C); create R/142_gantt_180_export.R writing gantt_episodes_180.csv + gantt_detail_180.csv with same 20/14-column schema as R/52 [EP-180-01, EP-180-02] (Wave 2, depends on 142-01)

### Phase 143: 180-Day File: Enrichment Parity and Review Follow-ups

**Goal:** Populate the six blank enrichment columns in the 180-day Gantt file (or remove them with documentation), verify patient-count and single-event-type invariants, document the episode definition with observed-maxima evidence, and investigate the Death-episode anomaly (1,300 to 1,299 across windows).
**Requirements**: EP-180-DISC-01, EP-180-ENRICH-01, EP-180-ENRICH-02, EP-180-EXPORT-01, EP-180-DOC-01
**Depends on:** Phase 142
**Plans:** 3/3 plans complete

Plans:
- [ ] 143-01-PLAN.md -- D-01 decision checkpoint (boundaries vs content); read-only discovery: producer disposition table, 90-day fill rates, death anomaly, patient-count reconciliation -> 143-DISCOVERY.md [EP-180-DISC-01] (Wave 1)
- [ ] 143-02-PLAN.md -- Parameterise R/28 (EPISODES_RDS_PATH / OUT_SUFFIX options, fix episode_number join keys); verify 90-day byte-identity; run 180-day enrichment pass on HiPerGator [EP-180-ENRICH-01, EP-180-ENRICH-02] (Wave 2, depends on 143-01, D-01b path only)
- [ ] 143-03-PLAN.md -- Wire enrichment join into R/142 or drop blank columns (D-01a/D-01b); write output/gantt_180_README.txt with episode rule + observed maxima; update 142-CONTEXT.md D-01 [EP-180-EXPORT-01, EP-180-DOC-01] (Wave 3, depends on 143-01 and 143-02)

### Phase 144: Centroid ZIP9 Imputation, ZIP9-Level SDI, and Areal-Mean SDI

**Goal:** Extend `approximate_zip9()` with a Tier 3 centroid ZIP9 imputation fallback (probe-first gated, new `zip9_source = "zip5_centroid"` value), and build a new standalone investigation script (R/116) that resolves ZIP9/ZIP5 per encounter and joins SDI, ADI, SVI, and RUCA SES index scores from staged reference files.
**Requirements**: none mapped in REQUIREMENTS.md (standalone investigation deliverable) — plans use 144-CONTEXT.md decision IDs (D-01..D-08) as acceptance criteria
**Depends on:** Phase 143
**Plans:** 3/3 plans complete

Plans:
- [x] 144-01-PLAN.md — Tier 3 centroid ZIP9 imputation in `utils_address.R`: Census ZCTA crosswalk README, `.centroid_zip9_lookup_cache`, `.empty_centroid_lookup()`, probe-first gate, `zip5_centroid` value in `.classify_zip9_source()`, 5 unit tests [D-01, D-02, D-03] (Wave 1)
- [x] 144-02-PLAN.md — R/116_encounter_ses_index.R: DuckDB ENCOUNTER pull, `get_zip9_at_date() |> approximate_zip9()`, probe-first SDI/ADI/SVI/RUCA joins, encounter-level RDS + 3-sheet xlsx [D-04, D-05, D-06, D-07, D-08] (Wave 2, depends on 144-01)
- [x] 144-03-PLAN.md — R/39 registration + SCRIPT_INDEX.md row + R/88 Section 15ae (21 structural smoke-test checks) [D-08] (Wave 3, depends on 144-01 + 144-02)

### Phase 145: R/116 Fan-Out Fix and SES Reference Gap Fill

**Goal:** Fix the 13.3% row-count inflation in R/116's encounter-SES join (fan-out from duplicate `(ID, query_date)` keys in `get_zip9_at_date()`), regenerate the corrected RDS and summary workbook, diagnose why the ZIP5-modal imputation tier fired zero rows, and document column contracts for the three absent SES reference files (SDI, SVI, ADI).
**Requirements**: FANOUT-01, ZIP5MODAL-01, SESDOC-01
**Depends on:** Phase 144
**Plans:** 3/3 plans complete

Plans:
- [x] 145-01-PLAN.md — Audit committed fan-out fix + trace ZIP5-modal path + document SDI/SVI/ADI reference contracts in README (Wave 1, autonomous)
- [x] 145-02-PLAN.md — Blocking HiPerGator checkpoint: run R/116, capture zip9_source breakdown + row-count guard (Wave 2)
- [x] 145-03-PLAN.md — Diagnose ZIP5-modal (data-driven vs bug), conditionally fix/document, regenerate corrected RDS + workbook (Wave 3)

### Phase 146: Acquire and Stage the SES Reference Files (SDI, SVI, ADI)

**Goal:** Acquire and stage the three absent SES reference files for R/116 — download SDI (ZCTA), derive SVI to ZCTA (CDC publishes no 2020 ZCTA file), and register-and-download ADI (ZIP9) — quantify each geography-mismatch haircut below the 77.7% ZIP ceiling, correct the 68.6% ADI figure to 77.7%, and re-run R/116 so each staged index reports honest sub-ceiling coverage while probe gates still degrade absent indices to NA.
**Requirements**: SES-01, SES-02, SES-03, SES-04
**Depends on:** Phase 145
**Plans:** 6/6 plans complete

Plans:
- [x] 146-01-PLAN.md — Discovery: verify SDI/SVI/ADI publications, network policy, sentinel-ZIP + normalizer-disagreement probes -> 146-DISCOVERY.md (Wave 1, autonomous)
- [ ] 146-02-PLAN.md — Human-action gate: D-02 (SVI method), ADI registration (P-03a), per-file redistribution rights (Wave 2)
- [ ] 146-03-PLAN.md — Stage SDI at data/reference/zip5_sdi_reference.csv + quantify ZIP5-with-no-ZCTA haircut + D-01 label (Wave 3)
- [ ] 146-04-PLAN.md — Derive SVI: R/147_build_svi_zcta.R + svi_2020_zcta_derived.csv with coverage floor (D-02a), or record drop (D-02c) (Wave 3)
- [ ] 146-05-PLAN.md — Wire R/116 to staged files + §4 ceiling sheet + rewrite README (derived SVI, D-01 SDI, 77.7% ADI) (Wave 4)
- [ ] 146-06-PLAN.md — HiPerGator re-run: R/116 + R/88 + sentinel-ZIP/SDI-unmatched queries against real data (Wave 5)
