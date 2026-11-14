---
phase: 203-no-treatment-patient-characterization
verified: 2026-11-14T00:00:00Z
status: passed
score: 7/7 must-haves verified
re_verification: false
---

# Phase 203: No-Treatment Patient Characterization — Verification Report

**Phase Goal:** The team has a complete, side-by-side profile of the approx. 3,246 confirmed-cohort patients with no captured treatment vs the 4,450 treated patients, with registry treatment fields joined and a candidate "treatment observable" eligibility rule documented for team decision — but not applied.
**Verified:** 2026-11-14
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #  | Truth                                                                                                       | Status     | Evidence                                                                                     |
|----|-------------------------------------------------------------------------------------------------------------|------------|----------------------------------------------------------------------------------------------|
| 1  | Schema probe of all Phase 203 inputs documented before join code is written                                 | VERIFIED   | `.planning/schemas/203_schema_PENDING.md` exists; names all 4 env vars + probe_inputs call   |
| 2  | Script splits confirmed cohort into no-treatment / treated with no cohort-membership change                 | VERIFIED   | `TX_COUNT_COL` split at lines 124–126; `stopifnot(nrow(no_tx) + nrow(treated) == nrow(cohort))` at line 131 |
| 3  | NOTX-01: window_truncated flag computed per patient for both groups                                         | VERIFIED   | `window_truncated` column derived at lines 212–220; `window_date_missing` guard present       |
| 4  | NOTX-02: encounters within ±90 days of dx counted per patient, summarized per group in bands                | VERIFIED   | DuckDB ENCOUNTER query (open/close_pcornet_con), inequality join, `enc_band` summary         |
| 5  | NOTX-03: no-treatment patients characterized by single_source_care, SOURCE, payer, far_from_care_100mi, age group, NLPHL/cHL — both groups side by side | VERIFIED   | Columns PAYER_CAT_COL, FAR_COL, SOURCE_COL, `age_group_dx`, `hl_subtype` all present on char_pt; summaries per group |
| 6  | NOTX-04: TR flags joined; `registry_says_tx_pipeline_missed` stratum named                                  | VERIFIED   | `TR_TX_COLS` with stop() guard; `registry_tx_given`; `registry_says_tx_pipeline_missed` at lines 413–414 |
| 7  | NOTX-05: proposed "treatment observable" rule documented with both-group counts, labelled not applied; NOTX-07: styled xlsx (KEY leftmost, A_profile, B_reasons_waterfall, C_by_source, D_candidate_rules, QC) written with <11 suppression; R/88 SECTION 15bf present | VERIFIED   | See artifact and key-link verification below                                                 |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact                                       | Expected                                                               | Status   | Details                                             |
|------------------------------------------------|------------------------------------------------------------------------|----------|-----------------------------------------------------|
| `R/203_no_treatment_characterization.R`        | Phase 203 full script: scaffold, characterization, workbook assembly   | VERIFIED | 837 lines; parses clean (rcheck.sh exits 0)         |
| `.planning/schemas/203_schema_PENDING.md`      | Probe placeholder listing all 4 inputs + probe_inputs call             | VERIFIED | File exists; grep count = 6 (all 4 env vars + probe call + PENDING string) |
| `R/SCRIPT_INDEX.md`                            | Table row for R/203 citing NOTX-01..NOTX-07                            | VERIFIED | Row present at line 189 with full NOTX coverage     |
| `R/88_smoke_test_comprehensive.R` SECTION 15bf | Phase 203 smoke checks: script, workbook, KEY-first, 4 sheets, QC, suppression | VERIFIED | SECTION 15bf at line 8219; inserted before SECTION 16 at line 8302; parses clean |

### Key Link Verification

| From                                    | To                                       | Via                                          | Status   | Details                                                      |
|-----------------------------------------|------------------------------------------|----------------------------------------------|----------|--------------------------------------------------------------|
| `R/203_no_treatment_characterization.R` | `R/00_config.R`                          | `source(here::here("R", "00_config.R"), local = FALSE)` | VERIFIED | Line 22                                                      |
| `R/203_no_treatment_characterization.R` | `confirmed_hl_cohort.rds`                | `R203_COHORT_RDS` env var + stop() guard      | VERIFIED | Lines 44–50; pin_info recorded                               |
| `R/203_no_treatment_characterization.R` | single_source_care RDS (R/169)           | left_join on ID; `single_source_care` column  | VERIFIED | Lines 304–310                                                |
| `R/203_no_treatment_characterization.R` | tr_lymphoma_flags RDS (R/193)            | left_join on ID; `TR_TX_COLS` guard          | VERIFIED | Lines 362–385; `TRFLAGS_RDS` env var                         |
| `R/203_no_treatment_characterization.R` | `output/203_no_treatment_characterization_<date>.xlsx` | `openxlsx` write; KEY sheet first | VERIFIED | Line 815 adds KEY first; lines 822–828 write dated filename  |
| `R/203_no_treatment_characterization.R` | `suppress_small()` / `fmt_sup()`         | display-time suppression on all patient counts | VERIFIED | Local `suppress_small` defined at line 524; applied at lines 542, 592–593 |
| `R/88_smoke_test_comprehensive.R`       | `output/203_no_treatment_characterization_<date>.xlsx` | file.exists + sheet-name checks | VERIFIED | Lines 8241–8299; glob pattern correct; absent-workbook path skips |

### Data-Flow Trace (Level 4)

| Artifact                                | Data Variable             | Source                                      | Produces Real Data      | Status    |
|-----------------------------------------|---------------------------|---------------------------------------------|-------------------------|-----------|
| `R/203_no_treatment_characterization.R` | `no_tx` / `treated`       | `readRDS(COHORT_RDS)`                       | HiPerGator RDS (pinned) | FLOWING   |
| `R/203_no_treatment_characterization.R` | `n_enc_peri_dx`           | DuckDB ENCOUNTER table via `duck_query()`   | Live DB query           | FLOWING   |
| `R/203_no_treatment_characterization.R` | `single_source_care`      | `readRDS(R169_RDS)` left-joined onto char_pt | HiPerGator RDS (pinned) | FLOWING   |
| `R/203_no_treatment_characterization.R` | `registry_tx_given`       | `readRDS(TRFLAGS_RDS)` left-joined onto char_pt | HiPerGator RDS (pinned) | FLOWING |

Note: All data sources require HiPerGator (pinned env vars with `stop()` guards on missing files). The IS_LOCAL guard stops the script cleanly on the local parse machine. This is expected behavior per CLAUDE.md.

### Behavioral Spot-Checks

| Behavior                                              | Command                                                                   | Result      | Status  |
|-------------------------------------------------------|---------------------------------------------------------------------------|-------------|---------|
| R/203 parses without errors                           | `tools/rcheck.sh parse R/203_no_treatment_characterization.R`             | 0 failures  | PASS    |
| R/88 parses without errors (includes SECTION 15bf)    | `tools/rcheck.sh parse R/88_smoke_test_comprehensive.R`                   | 0 failures  | PASS    |
| `treatment_observable` never used as a cohort filter  | `grep -c "filter(treatment_observable" R/203_no_treatment_characterization.R` | 0           | PASS    |
| DBI::dbDisconnect not used (use close_pcornet_con)    | `grep -c "DBI::dbDisconnect" R/203_no_treatment_characterization.R`       | 0           | PASS    |
| SECTION 15bf precedes SECTION 16                      | Line 8219 vs 8302 in R/88                                                 | Correct order | PASS  |

### Requirements Coverage

| Requirement | Source Plan(s) | Description                                                                 | Status    | Evidence                                               |
|-------------|----------------|-----------------------------------------------------------------------------|-----------|--------------------------------------------------------|
| NOTX-01     | 203-02         | window_truncated flag per no-treatment patient                              | SATISFIED | `window_truncated` column, `WINDOW_START_COL` guard, per-group summary |
| NOTX-02     | 203-02         | Encounter count within ±90 days of dx, summarized for no-treatment patients | SATISFIED | DuckDB query, inequality join, `enc_band` summary per group |
| NOTX-03     | 203-02         | No-treatment patients characterized by 6 dimensions                        | SATISFIED | PAYER_CAT_COL, FAR_COL, SOURCE_COL, age_group_dx, hl_subtype, single_source_care all on char_pt |
| NOTX-04     | 203-02         | Registry treatment join; registry-missed stratum named                      | SATISFIED | `TR_TX_COLS`, `registry_tx_given`, `registry_says_tx_pipeline_missed` |
| NOTX-05     | 203-03         | Proposed treatment-observable rule documented, not applied                  | SATISFIED | `treatment_observable` column; "RULE NOT APPLIED — proposed team decision item (D-203-01)" label; `filter(treatment_observable` grep = 0 |
| NOTX-06     | 203-01, 203-02 | Treated group (≥1 episode) included as comparison; all NOTX characteristics reported side by side | SATISFIED | Both `no_tx` and `treated` groups carry all NOTX-01..NOTX-04 columns; A_profile sheet has adjacent columns |
| NOTX-07     | 203-03, 203-04 | Styled xlsx with KEY leftmost + 4 content sheets + QC, <11 suppression; R/88 section | SATISFIED | Six sheets written in correct order; `suppress_small` applied; UF colours #0021A5/#FA4616; SECTION 15bf in R/88 |

No orphaned requirements. All 7 NOTX-01..NOTX-07 requirements are claimed across the four plans and evidenced in code.

### Anti-Patterns Found

| File                                    | Pattern                | Severity | Impact  | Assessment                                              |
|-----------------------------------------|------------------------|----------|---------|---------------------------------------------------------|
| `R/203_no_treatment_characterization.R` | `TR_TX_COLS` placeholder column names (`rx_summ_treatment_status`, `rx_summ_systemic_surg_seq`) | INFO | Low — stop() guard halts script if names absent; probe must confirm before HiPerGator run | Expected: probe was deferred to HiPerGator per plan design |
| `R/203_no_treatment_characterization.R` | `WINDOW_START_COL <- "enr_start_date"` placeholder | INFO | Low — stop() guard present | Expected: probe deferred to HiPerGator |

Both placeholders are guarded with `stop()` that prints available column names, as required. Neither is a silent stub; both are intentional pending-probe patterns per CLAUDE.md.

### Human Verification Required

#### 1. Schema probe execution on HiPerGator

**Test:** Run `probe_inputs("203", files = c(...))` in an interactive R/4.5 session on HiPerGator, then confirm column names `enr_start_date` (WINDOW_START_COL) and `rx_summ_treatment_status` / `rx_summ_systemic_surg_seq` (TR_TX_COLS) exist in the respective RDS files.
**Expected:** Probe writes `.planning/schemas/203_schema_<date>.md`; named constants in R/203 require no changes, or are updated to match confirmed names before the pipeline run.
**Why human:** Requires HiPerGator data access; local machine does not have the RDS files.

#### 2. Full pipeline run and workbook QC

**Test:** Source `R/203_no_treatment_characterization.R` in an interactive `module load R/4.5` session. Check console for the `no_tx` / `treated` row-count checkpoint, peri-dx encounter band summary, and the final file-path messages. Open the xlsx and verify KEY is leftmost, all six sheets are present, `<11` suppression tokens appear in A_profile, and the D_candidate_rules sheet shows the "RULE NOT APPLIED" label.
**Expected:** no_tx ≈ 3,246 and treated ≈ 4,450 (sum equals confirmed cohort total); workbook conforms to spec.
**Why human:** Pipeline data exists only on HiPerGator; workbook visual layout requires human inspection.

### Gaps Summary

No gaps. All plan must-haves are satisfied in the codebase:

- R/203 (837 lines) is substantive, parses clean, pins all four inputs, splits cohort with a membership-preserving assertion, computes all NOTX-01..NOTX-04 characteristics for both groups, documents NOTX-05 rule without applying it, and writes the styled six-sheet workbook with <11 suppression and UF colours.
- Schema probe placeholder (.planning/schemas/203_schema_PENDING.md) names all four inputs and the exact probe call.
- SCRIPT_INDEX.md row is registered with full NOTX coverage.
- R/88 SECTION 15bf is present, parses clean, and correctly precedes SECTION 16.
- Two placeholder column-name constants (WINDOW_START_COL, TR_TX_COLS) are guarded with stop() per CLAUDE.md probe-first convention and are expected to remain pending until the HiPerGator probe runs.

---

_Verified: 2026-11-14_
_Verifier: Claude (gsd-verifier)_
