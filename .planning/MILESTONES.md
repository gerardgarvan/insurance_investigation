# Milestones

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
