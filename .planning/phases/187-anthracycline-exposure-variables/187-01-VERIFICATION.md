---
phase: 187-anthracycline-exposure-variables
verified: 2026-10-22T00:00:00Z
status: passed
score: 7/7 must-haves verified
re_verification: false
---

# Phase 187: Anthracycline Exposure Variables — Verification Report

**Phase Goal:** Build patient-grain anthracycline exposure variables (any_chemo, any_anthracycline, last_anthracycline_date, years_since_last_anthracycline, drugs_received) joined from the treatment episode RDS to the survivorship cohort follow-up table, with suppressed aggregate workbook.
**Verified:** 2026-10-22
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every cohort patient has an `any_anthracycline` value of TRUE or FALSE (never NA) | VERIFIED | Script: `stopifnot(!anyNA(patient_out$any_anthracycline))` at line 267. Schema probe: `any_anthracycline` NA=0. HiPerGator run: TRUE=2,379 + FALSE=6,546 = 8,925 = total cohort. |
| 2 | Every cohort patient has an `any_chemo` value of TRUE or FALSE (never NA) | VERIFIED | Script: `stopifnot(!anyNA(patient_out$any_chemo))` at line 266. Schema probe: `any_chemo` NA=0. HiPerGator: TRUE=4,477 + FALSE=4,448 = 8,925. |
| 3 | Exposed patients have a non-NA `last_anthracycline_date` (max treatment_date across Doxorubicin/Daunorubicin/Epirubicin/Idarubicin rows) | VERIFIED | Script uses `last_dose_ever_dt` from `last_anthracycline_dose()` helper (line 164, 178). Guard at lines 198–202 stops if any exposed patient has NA last date. Schema probe: `last_anthracycline_date` NA=6,546 = the FALSE count for `any_anthracycline`, meaning all 2,379 exposed patients have a date. |
| 4 | `years_since_last_anthracycline` uses `follow_end` from `rates_parts$followup` — NA for unexposed; NA (not negative) when last dose is after `follow_end` | VERIFIED | Script reads `follow_end` from `rates_parts$followup` (lines 117–121). `if_else` at lines 189–193 sets NA when unexposed or `dose_after_end`. Guard at line 269: `all(years_since >= 0, na.rm=TRUE)`. Probe: NA=6,547 (6,546 unexposed + 1 D-07 flagged), min=0. |
| 5 | Output RDS lives in `output/internal/` and contains exactly one row per cohort patient | VERIFIED | Path: `here("output","internal","anthracycline_exposure_patient_{run_date}.rds")` (line 279–280). Guard: `stopifnot(nrow(patient_out) == nrow(followup))` (line 268). Probe: 8,925 rows, 8,925 distinct ID — one row per patient confirmed. |
| 6 | Aggregate summary (counts by flag and by drug, suppressed per HIPAA) written to `output/` with KEY sheet leftmost and UF colours | VERIFIED | Script builds `sup()` / `sup_pair()` helpers (lines 289–303). KEY sheet added first (line 410). UF_BLUE `#0021A5` and UF_ORANGE `#FA4616` defined lines 32–33 and applied to all sheet headers. COUNTS_BY_FLAG, COUNTS_BY_DRUG, FLAGS sheets built and written. SUMMARY confirms XLSX at `output/anthracycline_exposure_summary_20261022.xlsx`. |
| 7 | Output RDS path printed and recorded in `187-01-SUMMARY.md` for Phase 188 | VERIFIED | SUMMARY contains Phase 188 Interface section with exact path `output/internal/anthracycline_exposure_patient_20261022.rds` and pin variable name `R188_ANTH_RDS`. |

**Score:** 7/7 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/187_anthracycline_exposure.R` | Main script — four SECTION blocks, pins, fixtures, compute, write | VERIFIED | 445 lines. Contains SECTION 0–3. No `list.files` or `file.mtime`. |
| `output/internal/anthracycline_exposure_patient_20261022.rds` | Patient-grain RDS, internal | VERIFIED | 8,925 rows × 7 cols confirmed by schema probe. All required columns present. |
| `output/anthracycline_exposure_summary_20261022.xlsx` | Aggregate summary, no patient IDs | VERIFIED | Confirmed by HiPerGator run console output recorded in SUMMARY. |
| `.planning/schemas/187out_schema_20261022.md` | Output schema probe | VERIFIED | File present in repo. Shows column names, types, NA counts, value ranges. No patient-level values. |
| `.planning/phases/187-anthracycline-exposure-variables/187-01-SUMMARY.md` | Exact RDS path for Phase 188 | VERIFIED | Contains Phase 188 Interface block, `R188_ANTH_RDS` pin variable, schema probe reference, REG-01 handoff. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `R/187_anthracycline_exposure.R` | `cache/outputs/treatment_episode_detail_180.rds` | `readRDS(pin("R187_EPISODE_RDS", ...))` | VERIFIED | Lines 42–44 and 74. `stopifnot(file.exists(...))` guard at line 60. |
| `R/187_anthracycline_exposure.R` | `survivorship_modality_rates_parts_20261012.rds` | `readRDS(pin("R187_RATES_PARTS_RDS", ...))$followup` | VERIFIED | Lines 45–48 and 116–121. Deviation from plan documented: R/184 does not pin this file; R/187 uses R/166 output (Phase 171 SURV_RUN_DATE 20261012), noted in script header and SUMMARY. |
| `R/187_anthracycline_exposure.R` | `utils_anthracycline_echo.R::last_anthracycline_dose()` | `last_anthracycline_dose(chemo_episodes, ANTHRACYCLINE_DRUGS)` — returns `last_dose_ever_dt` stored as `last_anthracycline_date` | VERIFIED | Line 164 (call), line 178 (`last_dose_ever_dt` rename). All four drugs passed as `ANTHRACYCLINE_DRUGS` constant. |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| Patient-grain RDS | `any_anthracycline`, `years_since_last_anthracycline` | `last_anthracycline_dose()` applied to episode file rows filtered to `ANTHRACYCLINE_DRUGS` | Yes — 2,379 TRUE patients with dated rows from treatment episode detail; probe shows `last_anthracycline_date` range 2012-01-18 to 2025-03-27 | FLOWING |
| Patient-grain RDS | `any_chemo`, `follow_end` | Semi-join of episode IDs against `rates_parts$followup` | Yes — 4,477 chemo patients; `follow_end` range 2012-02-01 to 2025-04-10 from survivorship table | FLOWING |
| Aggregate XLSX | `n_patients` counts | `sup()` / `sup_pair()` applied to real patient_out column sums | Yes — values derive from patient_out which comes from above | FLOWING |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — No R on local Windows machine. HiPerGator run results serve as the behavioral evidence: script ran end-to-end without error, all five fixtures passed, output row counts equal followup row count (8,925), NA-flag guards passed, RDS and XLSX written successfully (confirmed by SUMMARY).

---

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| ANTH-01 | `any_anthracycline` and `any_chemo` (TRUE/FALSE, never NA) per cohort patient; drug set doxorubicin/daunorubicin/epirubicin/idarubicin (mitoxantrone excluded); aggregate counts suppressed per HIPAA | SATISFIED | `ANTHRACYCLINE_DRUGS` constant at line 67 (four drugs, Mitoxantrone absent). `any_anthracycline` never NA (guard + probe). `any_chemo` never NA (guard + probe). COUNTS_BY_FLAG and COUNTS_BY_DRUG sheets with `sup()` / `sup_pair()` suppression. |
| ANTH-02 | `last_anthracycline_date` = max treatment_date; `years_since_last_anthracycline` uses compute_followup `follow_end`; NA when unexposed or last dose after `follow_end` | SATISFIED | `last_dose_ever_dt` from helper provides max date per patient. `follow_end` from `rates_parts$followup` (D-11, does not reimplement compute_followup). NA logic in `if_else` lines 189–193. D-07 flag: 1 patient after follow_end has NA years. Probe: min=0, no negatives. |
| ANTH-03 | Patient-grain RDS in `output/internal/`; aggregate-only summary in `output/`; variables joined into survivorship analysis set; schema probe updated before code is written | SATISFIED | RDS at `output/internal/anthracycline_exposure_patient_20261022.rds` (ID + dates — internal). XLSX at `output/anthracycline_exposure_summary_20261022.xlsx` (no patient IDs). Schema probe `.planning/schemas/187out_schema_20261022.md` cited in script header. Phase 188 pin default recorded in SUMMARY for downstream join. |

All three requirements (ANTH-01, ANTH-02, ANTH-03) mapped from PLAN frontmatter are accounted for. No orphaned requirements for this phase.

---

### Anti-Patterns Found

| File | Pattern Checked | Result |
|------|-----------------|--------|
| `R/187_anthracycline_exposure.R` | `list.files` / `file.mtime` (CLAUDE.md anti-pattern) | ABSENT — grep returns 0 |
| `R/187_anthracycline_exposure.R` | `return null` / empty stub patterns | ABSENT — no empty handlers |
| `R/187_anthracycline_exposure.R` | `setwd` or absolute paths | ABSENT — uses `here()` throughout |
| `R/187_anthracycline_exposure.R` | Hardcoded empty `= []` / `= {}` for output variables | ABSENT — all output columns computed from real data |
| `output/internal/...rds` | Patient data outside `output/internal/` | ABSENT — RDS confirmed in internal path; XLSX confirmed in `output/` only |

No blocker or warning anti-patterns found.

---

### Human Verification Required

#### 1. XLSX KEY Sheet Position

**Test:** Open `output/anthracycline_exposure_summary_20261022.xlsx` in Excel.
**Expected:** KEY is the leftmost (first) tab; UF blue (`#0021A5`) header row on KEY; orange (`#FA4616`) header row on FLAGS.
**Why human:** Cannot open binary XLSX locally; sheet order and colour are visual.

#### 2. COUNTS_BY_DRUG Suppression for Small Combinations

**Test:** On COUNTS_BY_DRUG sheet, confirm that drug combinations present in fewer than 11 patients are shown as `"<11"`, and that zero-count drugs (Daunorubicin, Epirubicin, Idarubicin) show `"0"`.
**Why human:** Probe shows levels including `"Daunorubicin; Doxorubicin=<11"` — suppression of these multi-drug patients requires visual confirmation that COUNTS_BY_DRUG treats them correctly (counts are per drug, not per combination string).

These items are non-blocking. Automated verification of all seven must-have truths is complete and passed.

---

### Gaps Summary

No gaps. All seven observable truths are verified against the actual codebase and HiPerGator run evidence. All three requirements (ANTH-01, ANTH-02, ANTH-03) are satisfied. No blocker anti-patterns found.

---

_Verified: 2026-10-22_
_Verifier: Claude (gsd-verifier)_
