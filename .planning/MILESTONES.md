# Milestones

## v3.11 CBC Team Deliverable, Distance Completeness, Survivorship Modeling (Shipped: 2026-10-17)

**Phases completed:** Phases 181–184 (5 phases incl. 182.1), 13 plans

**Known gap:** Phase 184 Plan 02 HiPerGator checkpoint not confirmed before close-out; R/184 code written and fixed, formal SUMMARY pending. Resolved by Phase 185 (2026-10-22).

**Key accomplishments:**

- Patient-level prior-year CBC × far-from-care 2×2: OR 0.833 (95% CI 0.682–1.016, p=0.071) in survivorship cohort (year_index ≥ 2, N=7,075); team memo generated at runtime from Phase 179/180 workbook labels (Phase 181)
- Tier-1 facility ZIP fill (SOURCE+FACILITYID key, ≥3 supporting encounters, 1 distinct ZIP) wired into R/122; R/122→R/179→R/180 re-run; R/88 ALL 970 CHECKS PASSED (Phase 182)
- ZIP→ZCTA crosswalk fallback (HRSA 2022) added to R/122; 13,652 encounters resolved via crosswalk, 14 via haversine; placeholder ZIPs (000xx, 32800, etc.) classified missing; R/122→R/165→R/179→R/180→R/181 re-run; R/88 ALL 982 CHECKS PASSED (Phase 182.1)
- MICE multiple imputation (m=20, D-01 PMM / D-02 logreg): pooled primary ORs 0.842/0.834 (years 2+) within Phase 180 bounds, FMI 0.049/0.160 (low-moderate); confirms Phase 179 result robust to MAR assumption (Phase 183)
- Per-modality surveillance rate table (annual primary, 6-month sensitivity) + Poisson GEE far×modality interaction; R/184_modality_rate_model.R written and bug-fixed; HiPerGator close-out pending (Phase 184)

---

## v3.10 Distance Missingness & Script Fixes (Shipped: 2026-10-13)

**Phases completed:** 169 phases, 320 plans, 391 tasks

**Key accomplishments:**

- Context:
- Purpose:
- Commit:
- Purpose:
- Commit:
- Phase 102 (encounter-grain, 10 columns):
- Status:
- Files:
- Modified sections:
- >
- Task 1 — `R/utils/utils_address.R` (three edits):
- Invariants held:
- One-liner:
- One-liner:
- One-liner:
- One-liner:
- Verdict: PASS
- One-liner:
- One-liner:
- One-liner:
- Completeness waterfall (SECTION 11):
- One-liner:
- `R/utils/utils_distance_hist.R`
- One-liner:
- One-liner:
- One-liner:
- One-liner:
- load_lab_analytes() and load_modality_lookup() added to utils_surveillance.R with full validation; surveillance_codeset.xlsx (5 sheets, 167 rows) verified identical to Phase 158 in shared columns; Phase 158 callers and return type unchanged
- Four pure analyte-rule functions added to utils_surveillance.R with 8 test_that blocks (39 expectations) covering CMP nesting, partial-panel thresholds, duplicate-source dedup, KIDNEY eGFR sensitivity, near-miss format, anchor-day exclusion, and A2 row-level presence
- R/147 updated with Phase 159 analyte pull (Section 4B), an_rules bound into matched_all, A2 and E sheets, SC-4/SC-5/SC-6 stopifnots, and per-patient modality-dates .rds/.csv output
- R/88 Section 15ak (SMOKE-159-01) adds 9 structural checks enforcing Phase 159 lab modality design decisions; SCRIPT_INDEX updated; HiPerGator phase gate passed — 149 test expectations pass, R/88 Phase 159 9/9 PASS, R/147 runs cleanly for 9,331 patients, A/A2/near-miss reviewed, release workbook cleared.
- Task 1 — Codeset staging:
- Task 1 (RED) — Test file `tests/testthat/test-160-diagnostic-and-eligibility.R`:
- R/147_surveillance_modality_frequency.R — Phase 160 wiring (127 net insertions):
- R/88_smoke_test_comprehensive.R — Section 15al (Phase 160 block):
- Old (pre-161):
- 1. [Rule 2 - Missing functionality] DEATH_SOURCE collection
- R/52_gantt_v2_export.R
- One-liner:
- R/147 (T1, T2, T4):
- One-liner:
- Plan:
- One-liner:
- 1. [Rule 1 - Correction] Driver script number: R/166, not R/165
- One-liner:
- [Deviation - Minor] R/39 expected_xlsx not updated for dated workbook
- One-liner:
- One-liner:
- One-liner:
- 1. [Rule 1 - Bug] slurm/165 log name typo
- One-liner:
- One-liner:
- One-liner:
- One-liner:
- Script written:
- One-liner:
- 920 vs 921 discrepancy:
- Verdict: PASS
- Run date:
- One-liner:
- One-liner:
- R/147_verify_vs_1006.R sourced interactively on HiPerGator — session survived, confirming the !interactive() quit() guard from Plan 01 works correctly
- One-liner:
- One-liner:
- One-liner:

---

## v3.9 Pipeline Hygiene (Shipped: 2026-10-12)

**Phases completed:** 4 phases (Phases 174-177), 5 plans

**Delivered:** Closed four hygiene items deferred from v3.5–v3.8: fixed R/88 counter bugs that undercounted PASS by 43 checks; hardened R/88 with three-way exit guard, `skip_check()`, and `R88_FORCE_FAIL` sentinel; formally closed Phase 151 with a HiPerGator-confirmed PASS verdict; and confirmed NEEDS_TEMPORAL_MATCH sizing is Document only (zero fillable encounters — no new imputation tier warranted). R/.planning/ parallel planning tree identified, archived, and gitignored.

**Key accomplishments:**

- R/88 counter bugs in Sections 135/137/138/139/144 fixed (42 checks + 1 cache_dir check added); corrected baseline 963 CHECKS PASSED confirmed on HiPerGator; root cause of "921 vs 920" was IS_LOCAL branch difference, not a FAIL (Phase 174)
- Three-way exit guard added to R/88 (testthat no-op / interactive stop() / batch quit(status=1)); `skip_check()` replaces 13 fake-TRUE runtime-skips + 2 fake-assertions; `R88_FORCE_FAIL` sentinel for testing; new baseline 960 CHECKS PASSED (3 skipped) — all 4 HiPerGator paths confirmed (Phase 175)
- Phase 151 (Per-Patient ZIP Problem Inventory) formally closed: 151-01-SUMMARY.md written (Verdict: PASS), all 8 reconciliation quantities pass, 12 record-level mismatches accepted, Phase 151 ticked in ROADMAP (Phase 176)
- NEEDS_TEMPORAL_MATCH sizing: R/177 run on HiPerGator; 410 NEEDS_TEMPORAL_MATCH patients generate zero patient_zip_missing encounters in R/122 (address-history calendar already resolves their ZIPs); no new imputation tier warranted; 177-SIZING-MEMO.md and temporal_match_sizing_20261012.xlsx produced (Phase 177)
- R/.planning/ parallel planning tree (created when GSD was launched from R/ subdirectory) diagnosed, artifacts archived to root .planning/, R/.planning/ retired and gitignored; CLAUDE.md updated to prevent recurrence

---

## v3.8 Pipeline Refresh and Phase 130 Close-out (Shipped: 2026-10-12)

**Phases completed:** 4 phases (Phases 170-173), 7 plans

**Delivered:** R/147 surveillance re-run with a formal verification harness; survivorship
workbook refreshed and gated on the verified run; Phase 164 (doxorubicin generic-name
rename) confirmed in both 90-day and 180-day Gantts; Phase 130 DoI layer confirmed
registered and runtime-verified on HiPerGator against the 2026-07-16 baseline.

**Key accomplishments:**

- R/147 re-ran on HiPerGator (2026-10-09); verify harness (`R/147_verify_vs_1006.R`,
  `slurm/147_verify.sbatch`) returned 30 PASS / 0 FAIL — RFSH-01 cleared (Phase 170)

- Survivorship workbook refresh: R/166 wired to the Phase 170 gate via `r147_run_date`
  pointer; R/168 workbook assembler adds provenance KEY rows; `R/171_verify_survivorship.R`
  confirms 8/8 checks PASS — primary-tier rates and anthracycline-to-echo timing unchanged
  from 2026-10-08 reference — RFSH-02 closed (Phase 171)

- Phase 164 close-out: `doxorubicin` generic-name rename verified in 90-day Gantt
  (`gantt_episodes.csv`) and 180-day Gantt (`gantt_episodes_180.csv`) on HiPerGator
  (2026-10-12); `CUTOFF_DATE` env-var fix applied to standalone R/52 and R/142 runs;
  R/170 NHL subsets regression confirmed (Phase 172)

- Phase 130 DoI layer confirmed registered and runtime-verified: 920 R/88 checks PASS
  (pre-Phase 174 counting; baseline after v3.9 fixes is 960 passed, 3 skipped),
  SMOKE-130-01 footer confirmed, encounter-grain DoI counts exactly match 2026-07-16
  baseline — DuckDB unchanged; DOI-REG-01/02/03 closed (Phase 173)

---

## v3.7 Access, Survivorship Rates & NHL Episode Subsets (Shipped: 2026-10-09)

**Phases completed:** 5 phases (Phases 165-169), 10 plans

**Delivered:** >100 mi access indicator and CBC association analysis; per-patient
survivorship modality rates and anthracycline-to-echo timing workbook; single-health-system
care flag; NHL-only and HL+NHL Gantt episode subsets; R/165 pipeline registration,
SMOKE-165-01, and `88_smoke_test.sbatch`.

**Key accomplishments:**

- `far_from_care_100mi` column added to analysis set (cutoff locked by team 2026-10-08);
  primary method pending team confirmation (D-165-01; provisionally patient-level Fisher:
  OR 0.586 whole record / 0.659 post-anchor). Rao-Scott cluster-adjusted (DEFF ~130)
  reported alongside: OR 0.553 [0.470, 0.651] whole / 0.558 [0.468, 0.665] post-anchor.
  Payer covariate absent (no payer_summary RDS). `R/165_distance_cbc_association.R` +
  `utils_distance_cbc.R` (Phase 165)

- Survivorship modality rates: per-patient rates (post-primary tier), anthracycline-to-echo
  timing (D6/D7/D8 decision chain), complementary suppression;
  `R/166_survivorship_modality_rates.R` (Sections 1-5) + `R/168_survivorship_workbook.R`
  assembler; SMOKE-166-01 wired (Phase 166)

- Single health-system care flag: `build_single_source_result()` pure helper (TDD,
  7 test cases); encounter-band crosstabs whole-record and post-anchor;
  `R/169_single_source_care.R` + `slurm/167_single_source_care.sbatch` (Phase 167)

- NHL-only and HL+NHL Gantt episode subsets from `gantt_episodes_180.csv` joined to
  chemo-combos workbook via `norm_key()` + chemo-only E-J row-split/rejoin;
  `R/170_nhl_gantt_subsets.R` + `test-170-nhl-gantt-subsets.R` (Phase 168)

- R/165 registered in R/39 + SCRIPT_INDEX; SMOKE-165-01 (7 structural checks) +
  `test-165` unit tests; `88_smoke_test.sbatch` SLURM wrapper; all R/88 checks PASS
  on HiPerGator (Phase 169)

---

## v3.6 Treatment Episode Refinement (Superseded: 2026-10-08)

**Phases completed:** Phase 157 (closed without execution — commit `00adaeb`)

**Outcome:** Phase 157 was written to deliver 180-day treatment episodes and drug-name
deduplication. Phase 142 had already delivered `gantt_episodes_180.csv`,
`gantt_detail_180.csv`, and drug-name deduplication (all SUMMARY files present;
`R/142_gantt_180_export.R` delivered). Phase 157 was marked superseded on 2026-10-08
when the roadmap cleanup commit (`00adaeb`) noted it. No additional code produced.
`EPISODE-180-SPEC.md` scoping document remains in repo root.

---

## v3.5 Encounter Distance (AM §4) (Shipped: 2026-09-18)

**Phases completed:** Phases 152-154 complete; 155 superseded by Phase 165
(team chose >100 mi cutoff 2026-10-08); 156 (AM §4 write-back) dropped 2026-10-09

**Outcome:** Encounter-to-residence distance computed for all cohort encounters using
haversine-equivalent ZIP-centroid method (`utils_address.R`: `haversine_km()`,
`get_zip_centroid()`); patient ZIP calendar and best-ZIP selection rules implemented
(`utils_zip_calendar.R`); distribution histogram deliverable produced. Phase 155 (binary
indicator + cutoff memo) superseded by Phase 165. Phase 156 (AM §4 write-back) dropped
— AM §4 was scoped against a document that does not exist; REFERENCE_MANUAL in docs/ does
not use the §3/§4 decision-row structure; no further action planned.

---

## v3.4 R Pipeline Code Review Remediation (Shipped: 2026-07-25)

**Phases completed:** 5 phases (Phases 132-136), 7 plans

**Outcome:** Addressed all critical/high findings from a code review. Crash fixes:
NA-safe `min_or_na`/`max_or_na`, `R/53` death-before-birth guard, DuckDB UDF guard
(Phase 132). Wrong published number corrections: SCT filter, `total_records`, HL anchor
date, same-week desync, `age_at_episode`, empty reference manual (Phase 133). Ingest
integrity: DuckDB promotion gate hardened, 5 can't-fail validators fixed (Phase 134).
Cross-cutting patterns: 6/7 patterns standardized at shared-helper layer; Pattern A
(n_distinct de-duplication) accepted as a limitation — R/23 receives pre-aggregated
input, so it cannot be applied there (Phase 135). Loose ends confirmed: `date_range_max`
informational-only, no data dropped (Phase 136).

---

## Phases 137-151: Standalone ZIP/SES Investigations (2026-07-25 to 2026-10-12)

No milestone assigned. These 15 phases addressed the ZIP-code and SES data chain:
ZIP9 temporal assignment design (Phase 137), log-file cleanup (Phase 138), ZIP stability
counts workbook with C-02 reconciliation gate (Phases 139-140), context and design
documents (Phase 141), 180-day Gantt (Phase 142, retroactively closed v3.6),
180-day file enrichment (Phase 143), centroid ZIP9 crosswalk and areal-mean SDI
(Phase 144), SES reference file staging (Phases 145-146), ADDRESS_ZIP5 retraction
(Phase 147), centroid ZIP9 crosswalk tier 3 (Phase 148), sentinel-ZIP and ADI coverage
(Phase 149), ZIP5 concordance check (Phase 150), and per-patient ZIP problem inventory
(Phase 151, closed by Phase 176 on 2026-10-12). All produced planning artifacts and
outputs; none were scoped to a named milestone.

---

## v3.3 Rituximab/Methotrexate-Associated Diagnoses of Interest (Shipped: 2026-07-17)

**Phases completed:** 4 phases (Phases 127-130), 8 plans
**Milestone scope:** Additive, non-destructive DoI layer parallel to the cancer cascade — cancer classification, utils_cancer.R, and all existing outputs read-only throughout.

**Delivered:** Curated ICD-9/ICD-10 code set for rituximab/methotrexate non-malignant indications, a tested utility layer, encounter- and patient-grain classification artifacts from the real DIAGNOSIS table, a two-tier attribution linkage report, and full registration/smoke-test coverage — all gated behind a HiPerGator runtime pass confirming 709/709 R/88 checks.

**Key accomplishments:**

- `DOI_CODE_MAP` (35 keys, 14 clinical categories: RA, GPA/MPA vasculitis, pemphigus/pemphigoid, inflammatory myopathy, SLE, Sjogren's, NMO/MG, ITP/AIHA, psoriasis/PsA, IBD, plus edge conditions) + `DOI_CODE_TIER` + `RITUXIMAB_CODES` / `MTX_CODES` / `DOI_ATTRIBUTION_WINDOW_DAYS` (90L) centralized in `R/00_config.R`; I77.82 and D47.Z2 explicitly excluded with inline comments (Phase 127)
- `utils_doi.R` — `is_doi_code()` DX_TYPE-gated (ICD-9 `09` / ICD-10 `10`, NA/SNOMED -> FALSE) and `classify_doi_codes()` mirroring the `utils_cancer.R` cascade; local fixture exercises both ICD-9 (714.0) and ICD-10 (M05.9) paths (Phase 127)
- `R/111` — DuckDB-native `LEFT(DX,3) IN (...)` prefix pushdown before `collect()` (no full DIAGNOSIS table load); mutual-exclusivity hard-stop `sum(is_doi_code & is_cancer_code) == 0` confirmed **0** on real data; L10.81 `paraneoplastic_flag = TRUE`; writes `doi_encounters.rds` (encounter grain) and `doi_patients.rds` (patient grain) (Phase 128)
- `R/112` — two-tier attribution: ENCOUNTERID direct equi-join (tier 1) -> +/-90-day PATID temporal window via `DOI_ATTRIBUTION_WINDOW_DAYS` (tier 2); three-state `likely_non_lymphoma_directed` (TRUE/FALSE/NA, NA never coerced to FALSE); `attribution_method` column; 4-sheet `doi_attribution_report.xlsx` with co-occurrence language enforced and CAVEATS footnote on every sheet (Phase 129)
- R/88 Section 15w (14 checks: structural + IS_LOCAL-gated runtime), R/39 registration (R/111 before R/112), SCRIPT_INDEX rows; HiPerGator runtime confirmed — 10 DoI categories logged (Hematologic Autoimmune 10797, RA 5801, IBD 4128, Psoriasis 1740, Pemphigus 42); **709/709 R/88 checks pass** on real DIAGNOSIS data (Phase 130)

---

## v3.2 Meeting Gap Resolution Report (Shipped: 2026-07-15)

**Phases completed:** 23 phases (Phases 104-126), 37 plans, 61 tasks

**Delivered:** What began as a 4-phase charter (meeting gap investigations + a compiled RMarkdown report) grew into a 23-phase milestone that also reshaped pipeline outputs, enriched the cohort with rurality/ZIP geography, fixed the death-cause-NHL flag, closed the MED_ADMIN/DISPENSING chemo-detection gap end-to-end, and drove the R/88 comprehensive smoke test to exit 0.

**Key accomplishments:**

- Meeting gap investigations: pre-diagnosis treatment flagging + secondary-malignancy 7-day-gap table (Phase 104); Ethna/organ-transplant/SCT code verification + HL+NHL dual-code overlap validation (Phase 105); Tableau-ready encounter->cancer-code and chemo-drugs-by-class tables (Phase 106); RMarkdown gap-resolution report + delivery manifest + meeting-notes update (Phase 107)
- Pipeline hardening: zero-warning run via safe min/max wrappers + filename/sentinel fixes (Phase 108); date-grain co-administration analysis with non-specific ICD9 codes removed (Phase 109)
- Output reshaping: HL-only 7-day-confirmed V2 cancer summary (Phase 110); TABLE-2 collapsed to per-patient+date agents string (Phase 111); Gantt temporal-diagnosis enrichment + universal ascending alphabetical sort (Phase 112); post-death encounter temporal-gap investigation (Phase 113); drug-name consistency remediation via MEDICATION_LOOKUP + audit xlsx (Phase 114); Gantt 7-day-confirmed + age-at-episode columns (Phase 115)
- Enrichment: USDA 2020 RUCA rurality classification (Phase 116); lifespan Gantt collapse (Phase 117); Supportive Care meaning normalization via RxNav IN resolver (Phase 120); 9-digit ZIP change-frequency investigation (Phase 121)
- Death-cause NHL flag: three-state PATID flag CSV created (Phase 118) then fixed to source from the DEATH_CAUSE table (16th PCORNET_TABLES entry) instead of the non-existent DEATH.DEATH_CAUSE column — TRUE=5 / FALSE=57 / NA=1282 of 1344 deceased, was 100% blank (Phase 119)
- MED_ADMIN/DISPENSING chemo-detection fix: removed phantom RXNORM_CUI col_specs, added shared get_chemo_hits() + NDC->RxNorm crosswalk across 7 consumers (Phase 122); before/after fix-impact quantification + four-method unmatched-NDC audit (Phase 123); full downstream integration into episodes/Gantt/timing/regimens/payer/cohort with source-provenance labeling and canonical drug names (Phase 124) — **+1,328 patients / +13,762 chemo dates** vs the PRESCRIBING baseline
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
