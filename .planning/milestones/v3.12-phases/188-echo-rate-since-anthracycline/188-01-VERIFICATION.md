---
phase: 188-echo-rate-since-anthracycline
verified: 2026-10-27T00:00:00Z
status: human_needed
score: 7/7 must-haves verified (automated); 2 items need HiPerGator confirmation
re_verification: false
human_verification:
  - test: "Confirm outputs exist on HiPerGator"
    expected: "output/internal/echo_enc_anthracycline_20261022.rds (4,316 rows), output/internal/echo_rate_anthracycline_patient_20261022.rds (2,379 rows), output/20261022_188_echo_rate_anthracycline.xlsx each exist on the HiPerGator filesystem"
    why_human: "RDS and XLSX outputs are not present on the Windows repo clone; SUMMARY.md reports them as produced but local verification cannot confirm existence on HiPerGator"
  - test: "Confirm REQUIREMENTS.md checkboxes updated for ECHO-01 and ECHO-02"
    expected: "Both [ ] boxes in .planning/REQUIREMENTS.md changed to [x] for ECHO-01 and ECHO-02"
    why_human: "Both requirements remain unchecked in REQUIREMENTS.md on the local repo as of this verification; the script and SUMMARY satisfy the substance of both requirements but the status tracking has not been updated"
---

# Phase 188: Echo Rate Since Anthracycline Verification Report

**Phase Goal:** Among anthracycline-exposed patients (n=2,379 from Phase 187), compute echo rate per patient-year since last dose, add reconciliation columns for excluded echoes, and produce a four-sheet workbook (KEY, Rates, Anchor Comparison, QC). Also produces encounter-grain and patient-grain internal RDS files.
**Verified:** 2026-10-27
**Status:** human_needed (automated checks all pass; two HiPerGator-side items need confirmation)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Script sources cleanly with all 13 fixture cases passing before data load | VERIFIED | Fixtures 1–13 are all present in R/188_echo_rate_since_anthracycline.R lines 141–280; `message("Phase 188: all 13 fixture cases passed.")` at line 282; SUMMARY confirms passed on HiPerGator |
| 2 | Encounter-grain RDS contains deduplicated echo rows with window_label | VERIFIED | Script: `build_echo_out()` returns `encounter_grain` with `window_label` column (line 70); saved to `echo_enc_anthracycline_<date>.rds` (line 364–366); SUMMARY reports 4,316 rows |
| 3 | Patient-grain RDS contains required columns for every exposed patient; n_exposed read at run time, not hardcoded | VERIFIED | `pat` contains `n_echoes_post`, `person_years`, `rate_per_py`, `in_rate_population` (lines 113–117); `n_exposed <- nrow(anthra)` at line 319; hardcoded `2379` count: 0 matches |
| 4 | Fixtures and real data go through the same build_echo_out() function; SECTION 2-3 contain no duplicated logic | VERIFIED | `build_echo_out(anthra, echo_raw)` called once at line 351; grep for duplicated logic in SECTION 2-3 finds none; function defined once at lines 49–120 |
| 5 | D-06 sum checks and D-07a denominator check both pass (stop on failure) | VERIFIED | D-07a stop guards at lines 381, 383, 384, 386, 389; D-06 stop guards at lines 402, 404; SUMMARY records both passed with diff = 0 |
| 6 | Workbook has four sheets (KEY, Rates, Anchor Comparison, QC) with UF colours and suppressed counts | VERIFIED | `addWorksheet(wb, "KEY")` line 426, `"Rates"` line 493, `"Anchor Comparison"` line 518, `"QC"` line 685; UF_BLUE `#0021A5` line 415, UF_ORANGE `#FA4616` line 416; `sup()` and `sup_pair()` used throughout SECTION 4 |
| 7 | Anchor Comparison rows present for Phase 166 (from parts RDS) and Phase 188, per-patient overlap, and methodology table | VERIFIED | `anc_rows` tibble (lines 528–554) has Phase 166 row aggregated from `p166_rate`; `overlap_rows` (lines 570–588) has 6 overlap items; `meth` table (lines 591–642) has 8 methodology rows with citations or "not documented" pattern absent — Phase 166 entries all cite specific source files |

**Score:** 7/7 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/188_echo_rate_since_anthracycline.R` | Full pipeline script (fixtures + SECTION 0–4) | VERIFIED | 799 lines; exists locally; all sections present |
| `output/internal/echo_enc_anthracycline_20261022.rds` | Encounter-grain deduplicated echo events with window_label | HUMAN_NEEDED | Not present on Windows clone; SUMMARY reports 4,316 rows produced on HiPerGator 2026-10-22 |
| `output/internal/echo_rate_anthracycline_patient_20261022.rds` | Patient-grain rates for 2,379 exposed patients | HUMAN_NEEDED | Not present on Windows clone; SUMMARY reports 2,379 rows × 8 cols produced on HiPerGator |
| `output/20261022_188_echo_rate_anthracycline.xlsx` | Four-sheet workbook | HUMAN_NEEDED | Not present on Windows clone; SUMMARY reports written |

Note: absence of these files on the Windows repo is expected — they are HiPerGator outputs. The script code that writes them is fully wired and correct.

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| SECTION 1 anthra filter | `anthracycline_exposure_patient_20261022.rds` | `readRDS(R188_ANTHRA_EXPOSURE)` pin; `n_exposed <- nrow(anthra)` (no hardcoded count) | WIRED | Lines 313–319; pin at line 289–292 |
| SECTION 2 dedup | `dplyr::distinct(ID, echo_date)` | `inner_join` echo_raw onto anthra then `distinct` | WIRED | Lines 54–58 in `build_echo_out()`; called with real data at line 351 |
| SECTION 3 D-06 sum check | `nrow(echo_enc)` | sum of four `n_echoes_*` columns == encounter-grain row count | WIRED | Lines 392–405 |
| Anchor Comparison Phase 166 row | `survivorship_echo_parts_20261012.rds` | `pin R188_ANTHRA_166_PARTS`; filter `person_years > 0` | WIRED | Pin at lines 293–296; filter at line 521 |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| Patient-grain RDS | `pat` (n_echoes_post, person_years, rate_per_py) | `build_echo_out(anthra, echo_raw)` → anthra from Phase 187 RDS; echo_raw from dated_events RDS filtered to `"Echocardiogram"` | Yes — both RDS reads have `stopifnot(file.exists(...))` guards; filter uses schema-confirmed label | FLOWING |
| Rates sheet | `rate_pop`, `tot_echo`, `tot_py` | `dplyr::filter(pat, in_rate_population)` | Yes — derived from real `pat`; no static fallback | FLOWING |
| Anchor Comparison Phase 166 row | `p166_rate` | `echo_parts_166[[P166_ELEMENT]]` → filter `modality == P166_ECHO_LABEL` → filter `person_years > 0` | Yes — element name and echo label are named constants from probe (lines 339–340); `stopifnot(!anyDuplicated(p166$ID))` guard | FLOWING |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED for HiPerGator-side checks (no R on Windows). Fixture logic is confirmed wired (all 13 fixtures exist in script; SUMMARY confirms all passed). D-06 and D-07a stop guards are wired in script.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| ECHO-01 | 188-01-PLAN.md | Echo rate per patient-year since last anthracycline; echoes on/before last dose excluded and counted separately | SATISFIED | `build_echo_out()` computes `n_echoes_post / person_years`; `n_echoes_before_or_on_last_dose` is a reconciliation column; Rates sheet shows pooled rate |
| ECHO-02 | 188-01-PLAN.md | Reconciliation table vs Phase 166 anthracycline-to-echo timing; first- vs last-administration anchoring; differences explained in workbook KEY | SATISFIED | Anchor Comparison sheet has rate comparison, per-patient overlap (D-15a), and 8-row methodology table; KEY sheet records D-08a, PD-01, PD-02 |

**Note:** Both ECHO-01 and ECHO-02 remain unchecked (`[ ]`) in `.planning/REQUIREMENTS.md`. The implementation satisfies both; the checkbox update was not completed.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| R/188_echo_rate_since_anthracycline.R | 15 | Script header retains `188_166parts_schema_<date>.md` template placeholder in the comment block | Info | Comment only; actual code uses resolved constant `P166_ECHO_LABEL <- "echo_post_anthracycline"` at line 340. No functional impact. |

No stub implementations. No hardcoded patient counts. No `many-to-many` join warnings suppressed. No `TODO`/`FIXME` found.

---

### Human Verification Required

#### 1. HiPerGator Output File Existence

**Test:** On HiPerGator, confirm the three output files exist:
```
ls -lh output/internal/echo_enc_anthracycline_20261022.rds
ls -lh output/internal/echo_rate_anthracycline_patient_20261022.rds
ls -lh output/20261022_188_echo_rate_anthracycline.xlsx
```
**Expected:** All three present; encounter RDS ~ 4,316 rows, patient RDS ~ 2,379 rows.
**Why human:** Output files are on HiPerGator only; Windows local clone contains no RDS or XLSX outputs from any phase.

#### 2. REQUIREMENTS.md Checkbox Update

**Test:** Update `.planning/REQUIREMENTS.md` line 30 and 31 to `[x]` for ECHO-01 and ECHO-02.
**Expected:** Both requirements marked complete.
**Why human:** A code edit is required and cannot be done by the verifier without a GSD workflow.

---

### Gaps Summary

No functional gaps. All seven must-have truths are verified from the script code. The two items in the human verification section are:

1. **Output file confirmation on HiPerGator** — these files cannot be verified locally; the script code that writes them is fully correct and wired.
2. **REQUIREMENTS.md checkbox update** — a housekeeping edit, not a code gap. ECHO-01 and ECHO-02 are substantively satisfied.

The phase goal is achieved. The script is complete, the logic is correct, all 13 fixtures are present, all stop-on-failure guards are wired, the workbook structure matches the four-sheet requirement, and the Anchor Comparison contains all three required blocks (rate rows, per-patient overlap, methodology table).

---

_Verified: 2026-10-27_
_Verifier: Claude (gsd-verifier)_
