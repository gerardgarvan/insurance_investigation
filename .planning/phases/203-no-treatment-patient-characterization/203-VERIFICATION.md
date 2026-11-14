---
phase: 203-no-treatment-patient-characterization
verified: 2026-11-14T00:00:00Z
status: gaps_found
score: 6/7 requirements verified
gaps:
  - truth: "Schema probe confirmed before join code runs (probe-first per CLAUDE.md)"
    status: partial
    reason: >
      203_schema_PENDING.md is a placeholder only. No dated 203_schema_<date>.md
      was written before Plan 203-02 join code was committed. The TR_TX_COLS
      candidate names (rx_summ_treatment_status, rx_summ_systemic_surg_seq) and
      all six cohort column constants (WINDOW_START_COL, NLPHL_COL, AGE_DX_COL,
      PAYER_CAT_COL, FAR_COL, SOURCE_COL) are unconfirmed against real data.
      Stop() guards are in place and will catch mismatches on HiPerGator, but
      the CLAUDE.md probe-first rule is not satisfied until a dated schema file
      is committed and constants are updated to match.
    artifacts:
      - path: ".planning/schemas/203_schema_PENDING.md"
        issue: "Still PENDING — no resolved dated 203_schema_<date>.md exists"
    missing:
      - "Run probe_inputs('203', ...) on HiPerGator and commit the resulting 203_schema_<date>.md"
      - "Update TR_TX_COLS, WINDOW_START_COL, NLPHL_COL, AGE_DX_COL, PAYER_CAT_COL, FAR_COL, SOURCE_COL in R/203 to match confirmed column names"
human_verification:
  - test: "Schema probe resolution on HiPerGator"
    expected: "probe_inputs('203', ...) produces 203_schema_<date>.md; constants in R/203 updated to match; script runs without stop() on any column guard"
    why_human: "Probe requires real PCORnet CDM data on HiPerGator; local data access prohibited"
  - test: "Full pipeline run and workbook inspection on HiPerGator"
    expected: "Workbook written to output/; KEY is first sheet; A_profile has no_treatment and treated columns adjacent; D_candidate_rules first row is RULE NOT APPLIED label; all counts 1-10 shown as <11; char_pt RDS in output/internal/ only"
    why_human: "xlsx output only exists on HiPerGator after pipeline run"
  - test: "R/88 SMOKE-203-01 on HiPerGator after workbook produced"
    expected: "SMOKE-203-01: 6 PASS / 0 FAIL"
    why_human: "Checks [b]-[f] skip locally when workbook is absent"
---

# Phase 203: No-Treatment Patient Characterization Verification Report

**Phase Goal:** Characterize the no-treatment cohort and produce a styled workbook with side-by-side comparison (no-treatment vs treated), treatment-observable eligibility rule documentation, and suppressed outputs.
**Verified:** 2026-11-14
**Status:** gaps_found (1 gap — schema probe not resolved before join code)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Script splits confirmed cohort into no_tx / treated without changing membership | VERIFIED | Lines 124-136: filter on TX_COUNT_COL==0 / >=1 with stopifnot assertion |
| 2 | NOTX-01: window_truncated flag computed per patient for both groups | VERIFIED | Lines 211-231: window_truncated + window_date_missing on char_pt, per-group summary |
| 3 | NOTX-02: n_enc_peri_dx counted within +/-90 days via DuckDB + inequality join | VERIFIED | Lines 243-297: open_pcornet_con/close_pcornet_con, dplyr join_by, coalesce to 0 |
| 4 | NOTX-03: single_source_care, SOURCE, payer, far, age_group_dx, hl_subtype derived for both groups | VERIFIED | Lines 307-358: left_join R169, case_when age bands, if_else hl_subtype |
| 5 | NOTX-04: registry treatment join + registry_says_tx_pipeline_missed stratum | VERIFIED | Lines 366-433: TR_TX_COLS join, pivot_longer flag derivation, named stratum |
| 6 | NOTX-05: treatment_observable rule documented, not applied as filter | VERIFIED | Lines 458-513: column added to char_pt; grep -c "filter(treatment_observable" == 0; D-203-01 label present |
| 7 | NOTX-07: styled xlsx (KEY leftmost, 5 content sheets, <11 suppression, UF colours) + R/88 section | VERIFIED | Lines 547-837: all 6 sheets written KEY-first; 21 suppress_small calls; #0021A5/#FA4616 present; R/88 SECTION 15bf at line 8219 |
| 8 | Schema probe confirmed before join code (probe-first per CLAUDE.md) | FAILED | 203_schema_PENDING.md is unresolved; dated schema file absent; join code committed against candidate column names with stop() guards only |

**Score:** 7/8 truths verified (1 failed — probe-first rule not satisfied)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/203_no_treatment_characterization.R` | Main script: scaffold + NOTX-01..NOTX-05 + workbook | VERIFIED | 838 lines; parses clean (rcheck.sh exits 0) |
| `.planning/schemas/203_schema_PENDING.md` | Probe placeholder listing 4 inputs + probe call | VERIFIED (placeholder only) | Lists all 4 inputs + probe call; no resolved dated schema |
| `R/SCRIPT_INDEX.md` row for R/203 | SCRIPT_INDEX registration | VERIFIED | Line 189 confirmed; includes NOTX-01..NOTX-07 |
| `R/88_smoke_test_comprehensive.R` SECTION 15bf | Phase 203 smoke checks before SECTION 16 | VERIFIED | SECTION 15bf at line 8219; SECTION 16 at line 8302; parses clean |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| R/203 | R/00_config.R | source() at line 22 | WIRED | `source(here::here("R", "00_config.R"), local = FALSE)` |
| R/203 | confirmed_hl_cohort.rds | R203_COHORT_RDS + stop() guard | WIRED | Lines 62-67 |
| R/203 | R169 single_source_care RDS | R203_R169_RDS + left_join | WIRED | Lines 307-312 |
| R/203 | R193 TR flags RDS | R203_TRFLAGS_RDS + left_join | WIRED | Lines 366-384 |
| R/203 | DuckDB ENCOUNTER | open_pcornet_con/duck_query/close_pcornet_con | WIRED | Lines 243-250; DBI::dbDisconnect absent (0 matches) |
| R/203 | output/203_no_treatment_characterization_<date>.xlsx | openxlsx saveWorkbook | WIRED | Lines 822-825 |
| R/203 | output/internal/203_no_treatment_characterization_<date>.rds | saveRDS with "internal" subdir | WIRED | Lines 440-446 |
| R/88 SECTION 15bf | R/203 script existence | file.exists | WIRED | Line 8235-8236 |
| R/88 SECTION 15bf | 203 workbook sheets | openxlsx::getSheetNames | WIRED | Lines 8260-8275 |

---

### Data-Flow Trace (Level 4)

Data-flow cannot be verified locally (all PCORnet data on HiPerGator). Structural wiring confirmed:

- `char_pt` populated from readRDS(cohort), extended by DuckDB ENCOUNTER join, R169 join, TRFLAGS join — no hardcoded static returns
- `sheet_A` through `sheet_QC` derived from `char_pt` and per-group summaries — not from static values
- `suppress_small()` applied 21 times before every write_sheet call
- No `= []`, `= {}`, or `return JSON([])` empty-data stubs found

**Status: STRUCTURALLY WIRED.** Runtime verification requires HiPerGator (see Human Verification).

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| R/203 parses clean | tools/rcheck.sh parse R/203_no_treatment_characterization.R | 0 failed | PASS |
| R/88 parses clean | tools/rcheck.sh parse R/88_smoke_test_comprehensive.R | 0 failed | PASS |
| DBI::dbDisconnect absent | grep -c "DBI::dbDisconnect" R/203 | 0 | PASS |
| filter(treatment_observable absent | grep -c "filter(treatment_observable" R/203 | 0 | PASS |
| KEY added first to workbook | write_sheet call order at lines 815-820 | "KEY" first | PASS |
| All 6 sheet names in write calls | lines 815-820 | KEY, A_profile, B_reasons_waterfall, C_by_source, D_candidate_rules, QC | PASS |
| RULE NOT APPLIED label present | grep "RULE NOT APPLIED" R/203 | 7 matches | PASS |
| suppress_small called on all count output | grep -c "suppress_small" R/203 | 21 matches | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| NOTX-01 | 203-02 | window_truncated flag for both groups | SATISFIED | char_pt.window_truncated + window_date_missing; notx01_summary per group |
| NOTX-02 | 203-02 | Encounters +-90 days of dx per patient | SATISFIED | n_enc_peri_dx via DuckDB inequality join; PERI_DX_WINDOW_DAYS <- 90L |
| NOTX-03 | 203-02 | single_source_care, SOURCE, payer, far, age_group_dx, hl_subtype for both groups | SATISFIED | Lines 307-358; 6 characteristics computed per group |
| NOTX-04 | 203-02 | Registry treatment join + pipeline-missed stratum | SATISFIED | registry_says_tx_pipeline_missed derived and named; notx04_summary |
| NOTX-05 | 203-03 | treatment_observable rule proposed, not applied | SATISFIED | Column on char_pt; never used as filter (0 filter() matches); D-203-01 label in workbook |
| NOTX-06 | 203-01 | Both groups (no_treatment + treated) in every characteristic | SATISFIED | char_pt carries group; every summary grouped_by(group); A_profile pivots both to adjacent columns |
| NOTX-07 | 203-03, 203-04 | Styled xlsx (KEY leftmost, 5 content sheets + QC) with <11 suppression; R/88 section | SATISFIED (pending HiPerGator run) | Workbook assembly complete in R/203; SECTION 15bf in R/88; both parse clean |

All 7 NOTX requirements addressed in code. Full NOTX-07 satisfaction requires HiPerGator run to confirm workbook writes correctly.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| R/203 | 234, 300, 350-358, 429 | print() of raw per-group summary frames (unsuppressed counts may include 1-10) | INFO | Console only; not in workbook; no patient IDs; per CLAUDE.md suppress-after-arithmetic, suppression only required at display-time outputs. Not a blocker. |
| .planning/schemas/ | — | No resolved 203_schema_<date>.md | BLOCKER (HiPerGator) | Join code uses candidate column names with stop() guards. Script will halt on HiPerGator if any candidate name does not match real data. Must resolve before pipeline run. |

---

### Human Verification Required

#### 1. Schema Probe Resolution

**Test:** In a HiPerGator interactive R/4.5 session, source R/00_config.R and R/utils/utils_schema_probe.R, then run the probe_inputs("203", ...) call from .planning/schemas/203_schema_PENDING.md.
**Expected:** Resulting 203_schema_<date>.md committed; constants TX_COUNT_COL, WINDOW_START_COL, NLPHL_COL, AGE_DX_COL, PAYER_CAT_COL, FAR_COL, SOURCE_COL, TR_TX_COLS updated in R/203 to match confirmed names; script runs without stop() on any column guard.
**Why human:** Probe must run against real PCORnet CDM data on HiPerGator; local data access prohibited by CLAUDE.md.

#### 2. Full Pipeline Run and Workbook Inspection

**Test:** Source R/203_no_treatment_characterization.R in an interactive R/4.5 session on HiPerGator.
**Expected:** Workbook written to output/; KEY is first sheet; A_profile has no_treatment and treated count columns adjacent; B_reasons_waterfall has 4 rows; D_candidate_rules first row is the RULE NOT APPLIED label; all counts 1-10 appear as "<11"; char_pt RDS is in output/internal/ only and not in the xlsx.
**Why human:** xlsx output only exists on HiPerGator after pipeline run.

#### 3. R/88 SMOKE-203-01 on HiPerGator

**Test:** Source R/88_smoke_test_comprehensive.R on HiPerGator after workbook is produced.
**Expected:** SMOKE-203-01 reports 6 PASS / 0 FAIL.
**Why human:** Checks [b]-[f] in SECTION 15bf skip locally when the workbook is absent.

---

### Gaps Summary

One gap: the schema probe was not resolved before Plan 203-02 join code was written.

CLAUDE.md requires that probe_inputs() runs on HiPerGator and produces a dated 203_schema_<date>.md before any join code references column names. The 203-02 SUMMARY acknowledges this as a known deviation — both tasks were written against candidate column names with stop() guards that will halt and print available columns if any name differs from real data. The stop() guards are correctly implemented and prevent silent wrong-column reads.

The gap closes when:
1. probe_inputs("203", ...) runs on HiPerGator
2. 203_schema_<date>.md is committed
3. R/203 column constants are updated to match confirmed names
4. R/203 runs end-to-end without hitting any stop() guard

No other gaps found. All NOTX-01 through NOTX-07 requirements are implemented in code. Privacy rules (patient-level RDS in output/internal/ only), suppression (21 suppress_small calls, deferred to display time), UF colours (#0021A5/#FA4616), KEY-leftmost sheet order, DBI::dbDisconnect prohibition, and no-filter-on-treatment_observable rule are all verified in the codebase.

---

_Verified: 2026-11-14_
_Verifier: Claude (gsd-verifier)_
