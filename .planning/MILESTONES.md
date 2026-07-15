# Milestones

## v3.2 Meeting Gap Resolution Report (Shipped: 2026-07-15)

**Phases completed:** 23 phases (Phases 104-126), 37 plans, 61 tasks

**Delivered:** What began as a 4-phase charter (meeting gap investigations + a compiled RMarkdown report) grew into a 23-phase milestone that also reshaped pipeline outputs, enriched the cohort with rurality/ZIP geography, fixed the death-cause-NHL flag, closed the MED_ADMIN/DISPENSING chemo-detection gap end-to-end, and drove the R/88 comprehensive smoke test to exit 0.

**Key accomplishments:**

- Meeting gap investigations: pre-diagnosis treatment flagging + secondary-malignancy 7-day-gap table (Phase 104); Ethna/organ-transplant/SCT code verification + HL+NHL dual-code overlap validation (Phase 105); Tableau-ready encounter→cancer-code and chemo-drugs-by-class tables (Phase 106); RMarkdown gap-resolution report + delivery manifest + meeting-notes update (Phase 107)
- Pipeline hardening: zero-warning run via safe min/max wrappers + filename/sentinel fixes (Phase 108); date-grain co-administration analysis with non-specific ICD9 codes removed (Phase 109)
- Output reshaping: HL-only 7-day-confirmed V2 cancer summary (Phase 110); TABLE-2 collapsed to per-patient+date agents string (Phase 111); Gantt temporal-diagnosis enrichment + universal ascending alphabetical sort (Phase 112); post-death encounter temporal-gap investigation (Phase 113); drug-name consistency remediation via MEDICATION_LOOKUP + audit xlsx (Phase 114); Gantt 7-day-confirmed + age-at-episode columns (Phase 115)
- Enrichment: USDA 2020 RUCA rurality classification (Phase 116); lifespan Gantt collapse (Phase 117); Supportive Care meaning normalization via RxNav IN resolver (Phase 120); 9-digit ZIP change-frequency investigation (Phase 121)
- Death-cause NHL flag: three-state PATID flag CSV created (Phase 118) then fixed to source from the DEATH_CAUSE table (16th PCORNET_TABLES entry) instead of the non-existent DEATH.DEATH_CAUSE column — TRUE=5 / FALSE=57 / NA=1282 of 1344 deceased, was 100% blank (Phase 119)
- MED_ADMIN/DISPENSING chemo-detection fix: removed phantom RXNORM_CUI col_specs, added shared get_chemo_hits() + NDC→RxNorm crosswalk across 7 consumers (Phase 122); before/after fix-impact quantification + four-method unmatched-NDC audit (Phase 123); full downstream integration into episodes/Gantt/timing/regimens/payer/cohort with source-provenance labeling and canonical drug names (Phase 124) — **+1,328 patients / +13,762 chemo dates** vs the PRESCRIBING baseline
- R/88 smoke test: stale DEATH_CAUSE guard check (Section 15o Check 6) rewritten to the table-availability assertion (Phase 125); stale episode_classification_audit.xlsx regenerated so R/88 exits 0 (Phase 126)

**Git range:** `400b1f9..HEAD` (330 commits, 68 `feat(`, 2026-06-15 to 2026-07-15)
**Code:** 254 files changed, +52,863 / -1,039 lines

### Known Gaps

- **Phase 126** (regenerate stale `episode_classification_audit.xlsx` so R/88 exits 0) shipped without GSD artifacts — no PLAN/SUMMARY/VERIFICATION; the fix ran as a manual HiPerGator data refresh and the R/88 exit-0 pass is attested only in prose (STATE.md / user confirmation), not repository-verifiable. Accepted as verified-by-prose-only per audit path B.
- **Runtime-deferred (structural PASS only, HiPerGator run pending):** Phases 106, 107, 108, 111, 113, 117, 120, 121 — output files / HTML render / row-count checks not yet produced on the dev host. Worth a single consolidated HiPerGator run.

---

## v2.3 Gantt Data Enrichment (Shipped: 2026-06-08)

**Phases completed:** 4 phases, 4 plans, 4 tasks

**Key accomplishments:**

- (none recorded)

---

## v2.2 Local Testing Infrastructure & Clinical Refinements (Shipped: 2026-06-05)

**Phases completed:** 7 phases (Phases 83-89), 11 plans

**Delivered:** Environment auto-detection for local Windows vs HiPerGator Linux, 20-patient hand-crafted test fixtures, DuckDB integration validation, end-to-end local test runner, unified ICD-9/ICD-10 cancer code handling, instance-level drug grouping tables, and episode vs encounter grain labeling for output files.

**Key accomplishments:**

- Environment auto-detection (IS_LOCAL flag via Sys.info() with R_TESTING_ENV override), conditional paths for data/cache/DuckDB, 1-thread local vs SLURM-allocated production (Phase 83)
- 20-patient hand-crafted test fixtures covering 11 clinical edge cases across 15 PCORnet CDM tables with documented FIXTURE_DESIGN.md (Phase 84)
- DuckDB integration validation (R/88 Sections 32-33) and end-to-end local test runner (tests/run_local_test.R) with fixture schema assertions (Phase 85)
- v2.2 quality standards validation and milestone documentation (Phase 86)
- Unified ICD-9/ICD-10 cancer code handling via shared utils_cancer.R with is_cancer_code() and 4-tier classify_codes() cascade, HL cohort expanded to C81 + 201.x (Phase 87)
- Instance-level drug grouping tables (R/57) with human-readable sub-category and cancer site category names (Phase 88)
- Episode vs encounter grain labeling with self-documenting filenames, grain-prefixed sheet names, and backward-compatible old filenames (Phase 89)

**Git range:** `840fee1..2e442b1` (92 commits, 2026-06-03 to 2026-06-05)
**Code:** 86 files changed, +17,865 / -2,424 lines

---

## v1.8 Episode-Level Cancer Linkage & First-Line Therapy Identification (Shipped: 2026-06-01)

**Phases completed:** 4 phases (Phases 60-63), 6 plans

**Delivered:** Encounter-level cancer linkage, first-line HL regimen identification (ABVD, BV+AVD, Nivo+AVD), first-line therapy flagging for adults 21+, death date analysis tables, and Gantt v2 CSV export with all enhancements.

**Key accomplishments:**

- ENCOUNTERID propagation through treatment episodes + drug name resolution via RxNorm API with standalone lookup table (Phase 60)
- Encounter-level cancer linkage replacing patient-level joins, using ENCOUNTERID direct match + 30-day temporal fallback (Phase 61)
- First-line HL regimen detection (ABVD, BV+AVD, Nivo+AVD) with dropped-agent tolerance, added-agent disqualification, and temporal availability rules (Phase 61)
- First-line therapy flagging for adults 21+ with 60-day clean period + death date data quality analysis (1,295 validated deaths, 253 with post-death activity) (Phase 62)
- Gantt v2 CSV export with encounter-level cancer categories, regimen labels, first-line flags, and Death/HL Diagnosis pseudo-treatment rows (Phase 63)

**Git range:** `57e505a..31bab97` (21 commits, 2026-05-29 to 2026-06-01)
**Code:** 2,153 LOC R (4 scripts: R/60, R/61, R/62, R/63) + modifications to R/43a, R/44a, R/00_config.R, R/49

---

## v1.5 Payer Analysis Expansion (Shipped: 2026-05-01)

**Phases completed:** 4 phases (Phases 34-37), 4 plans, 5 tasks

**Delivered:** Payer code frequency analysis, hierarchical same-day payer resolution with Amy Crisp framework, AMC 8-category centralized mapping, and 8-tier resolution hierarchy with distinct Other govt tier.

**Key accomplishments:**

- Standalone payer code frequency diagnostic with PayerVariable.xlsx cross-reference for AV+TH encounters (Phase 34)
- Dual-scope (all encounters + AV+TH) frequency tables and hierarchical same-day payer resolution per Amy Crisp framework (Phase 35)
- Centralized AMC 8-category payer mapping in R/00_config.R, eliminating runtime PayerVariable.xlsx dependency (Phase 36)
- 8-tier resolution hierarchy with distinct "Other govt" tier for government program visibility (Phase 37)

**Git range:** `549c926..8af61f3` (6 code commits, 2026-04-26 to 2026-05-01)
**Code:** 787 LOC R (2 scripts: R/35_payer_code_frequency_av_th.R, R/36_tiered_same_day_payer.R) + 162-line R/00_config.R expansion

---

## v1.4 AV+TH Subset Analysis (Shipped: 2026-04-27)

**Phases completed:** 1 phase (Phase 33), 2 plans, 2 tasks

**Delivered:** AV+TH-restricted multi-source overlap detection and classification scripts with preserved baseline outputs.

**Key accomplishments:**

- AV+TH multi-source overlap detection (R/33) with same-date and same-week encounter pair identification for outpatient encounters
- Identical/Partial/Distinct classification (R/34) for AV+TH multi-source encounters with per-site recommendations
- Established ENC_TYPE subset analysis pattern (clone-and-filter with `_av_th` suffix) reusable for future encounter type analyses
- 13/13 AVTH requirements completed (AVTH-DET-01 through 06, AVTH-CLS-01 through 07)

**Git range:** `e7d2af4..bca6819` (13 commits, 2026-04-23 to 2026-04-24)
**Code:** 1,242 LOC R (2 scripts: R/33_multi_source_overlap_av_th.R, R/34_overlap_classification_av_th.R)

---
