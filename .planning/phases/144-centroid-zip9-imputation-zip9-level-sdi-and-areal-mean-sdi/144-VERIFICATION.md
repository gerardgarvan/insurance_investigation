---
phase: 144-centroid-zip9-imputation-zip9-level-sdi-and-areal-mean-sdi
verified: 2026-08-17T00:00:00Z
status: passed
score: 8/8 must-haves verified
re_verification: false
---

# Phase 144: Centroid ZIP9 Imputation + Encounter SES Index — Verification Report

**Phase Goal:** Extend `approximate_zip9()` with a Tier 3 centroid fallback (`zip9_source = "zip5_centroid"`), write `R/116_encounter_ses_index.R` for encounter-level SES index linkage (SDI, ADI, SVI, RUCA), and register the script.
**Verified:** 2026-08-17
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `approximate_zip9()` has a Tier 3 centroid fallback that assigns `zip9_source = "zip5_centroid"` when the modal lookup misses but a centroid crosswalk hit exists | VERIFIED | `utils_address.R` line 279: `!is.na(centroid_zip9) ~ "zip5_centroid"` |
| 2 | Tier 3 is probe-first gated: absent crosswalk degrades gracefully, not an error | VERIFIED | `utils_address.R` line 493: `if (file.exists(centroid_path))` with `.empty_centroid_lookup()` fallback on both absent and parse-failure paths |
| 3 | A 0000 guard rejects synthetic ZIP9s in any staged crosswalk | VERIFIED | `utils_address.R` lines 539–546: guard reads `centroid_lookup$centroid_zip9`, checks `grepl("0000$", ...)`, stops with "synthetic placeholders" message |
| 4 | `R/116_encounter_ses_index.R` exists and implements the full encounter-level SES linkage pipeline | VERIFIED | File exists; contains `get_zip9_at_date` + `approximate_zip9` chain, all 4 probe gates (`has_ruca`, `has_sdi`, `has_adi`, `has_svi`), output paths matching D-06 naming convention, and `addr_ids` scoping |
| 5 | R/116 joins SDI/SVI on ZIP5 and ADI on ZIP9 | VERIFIED | `R/116_encounter_ses_index.R` line 271: `ruca_lookup … by = "ZIP5"`; line 277: `adi_lookup … by = "ZIP9"` |
| 6 | R/116 is registered in R/39's `investigation_scripts` vector | VERIFIED | `R/39_run_all_investigations.R` line 221 |
| 7 | R/116 has a row in `R/SCRIPT_INDEX.md`; script count matches actual table rows (17) | VERIFIED | `R/SCRIPT_INDEX.md` line 162 (row present); stated count "17" equals 17 table rows |
| 8 | SECTION 15ae smoke-test block is present in R/88 with 21 `check_144()` calls; SECTION 16 intact | VERIFIED | `R/88_smoke_test_comprehensive.R` line 5000 (SECTION 15ae); 21 `check_144(` calls confirmed; SECTION 16 at line 5119 |

**Score:** 8/8 truths verified

---

### Required Artifacts

| Artifact | Provides | Status | Details |
|----------|----------|--------|---------|
| `R/utils/utils_address.R` | Tier 3 centroid extension to `approximate_zip9()` and `.classify_zip9_source()` | VERIFIED | Cache object at line 241; `centroid_lookup` param at line 247; probe gate at line 493; summary counter at line 570 |
| `data/reference/README_zip5_centroid_zip9_crosswalk.txt` | Derivation methodology for the centroid crosswalk (human action on HiPerGator) | VERIFIED | File exists with full derivation spec including rejection of "0000" append anti-pattern |
| `R/116_encounter_ses_index.R` | Encounter-level SES index linkage script | VERIFIED | Substantive — full 10-section implementation; 330+ lines |
| `tests/testthat/test-utils-address-tier3.R` | Unit tests for Tier 3 centroid logic | VERIFIED | 9 `test_that()` calls (exceeds required 5); tests cover `zip5_centroid` fires, `zip5_no_zip9` fallback, priority ordering, row-count guard, and 0000 guard |
| `R/39_run_all_investigations.R` | R/116 registration | VERIFIED | Line 221 contains `R/116_encounter_ses_index.R` in `investigation_scripts` |
| `R/SCRIPT_INDEX.md` | R/116 documentation row | VERIFIED | Line 162 present; stated count 17 matches actual 17 table rows |
| `R/88_smoke_test_comprehensive.R` | SECTION 15ae structural smoke tests | VERIFIED | 21 checks; SECTION 16 follows immediately after |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `approximate_zip9()` | `.classify_zip9_source()` | `centroid_lookup` parameter | WIRED | Line 550 passes `centroid_lookup = centroid_lookup` |
| `approximate_zip9()` | centroid crosswalk file | probe gate + vroom load | WIRED | Lines 493–532 |
| `.classify_zip9_source()` | `zip9_source = "zip5_centroid"` | `case_when` Tier 3 branch | WIRED | Line 279 |
| `R/116` | `get_zip9_at_date() \| approximate_zip9()` | direct call chain | WIRED | Lines 126–129 |
| `R/116` | RUCA/SDI/SVI/ADI reference files | probe gates + left_join | WIRED | Lines 79–82 (gates), 271–277 (joins) |
| `R/116` | R/39 `investigation_scripts` | string entry | WIRED | Line 221 of R/39 |
| `R/88` SECTION 15ae | `R/116`, `utils_address.R`, test file | `read_or_null()` + `check_144()` | WIRED | Lines 5024–5028 load files; 21 checks fire |

---

### Data-Flow Trace (Level 4)

R/116 renders dynamic data from DuckDB + reference files. The data flow is verifiable structurally:

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `R/116_encounter_ses_index.R` | `encounters_raw` | `get_pcornet_table("ENCOUNTER")` filtered via `addr_ids` | Yes (DuckDB query; guarded with `stopifnot nrow > 0`) | FLOWING |
| `R/116_encounter_ses_index.R` | `encounter_zip` | `get_zip9_at_date() \| approximate_zip9()` | Yes (live resolution via utils_address chain) | FLOWING |
| `R/116_encounter_ses_index.R` | `ruca_lookup` | `readxl::read_excel(RUCA_PATH)` | Yes (real file load; `distinct(ZIP5)` deduplication) | FLOWING |
| `R/116_encounter_ses_index.R` | `sdi_lookup`, `svi_lookup`, `adi_lookup` | `vroom::vroom()` on probe-gated reference files | Yes when present; empty tibble (correct column types) when absent — scores become NA, not fabricated | FLOWING |

Note: Tier 3 (`zip5_centroid`) is structurally wired but inert at runtime because `zip5_centroid_zip9_crosswalk.csv` does not yet exist (requires a licensed ZIP+4 source as documented in README). ADI (`adi_natrank`) will be entirely null for the same reason plus pending P-03a acquisition of the Neighborhood Atlas crosswalk. This is the honest state documented in 144-CONTEXT.md D-01.

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — no runnable entry points available locally (requires HiPerGator with ENCOUNTER DuckDB table and LDS_ADDRESS_HISTORY CSV).

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| ZIP9-T3-01 | 144-01 | Tier 3 centroid cache object in `utils_address.R` | SATISFIED | `utils_address.R` line 241: `.centroid_zip9_lookup_cache` |
| ZIP9-T3-02 | 144-01 | `.classify_zip9_source()` extended with `centroid_lookup` param and `zip5_centroid` tier | SATISFIED | Lines 247–290 |
| ZIP9-T3-03 | 144-01 | `approximate_zip9()` loads crosswalk probe-first, passes to classify, summary includes counter | SATISFIED | Lines 490–570 |
| SES-01 | 144-02 | `R/116_encounter_ses_index.R` exists with encounter pull via DuckDB | SATISFIED | File exists; SECTION 4 uses `get_pcornet_table("ENCOUNTER")` |
| SES-02 | 144-02 | ZIP9 resolution via `get_zip9_at_date() \| approximate_zip9()` per encounter | SATISFIED | Lines 126–129 |
| SES-03 | 144-02 | SES joins (SDI ZIP5, ADI ZIP9, SVI ZIP5, RUCA ZIP5) with probe gates | SATISFIED | Lines 79–82 (gates), 271–277 (joins) |
| SES-04 | 144-02 | Output: dated RDS + 3-sheet XLSX at D-06 naming convention | SATISFIED | Lines 61–62, 290–340 |
| SES-05 | 144-03 | R/116 registered in R/39; row in SCRIPT_INDEX.md; SECTION 15ae in R/88 | SATISFIED | All three verified above |

---

### Anti-Patterns Found

No blockers or warnings. Spot checks on R/116 and utils_address.R:

| File | Pattern Checked | Result |
|------|-----------------|--------|
| `R/116_encounter_ses_index.R` | `get_hl_patient_ids` call (forbidden per D-07) | Clean — 0 occurrences |
| `R/116_encounter_ses_index.R` | R/116 in `expected_xlsx` in R/39 (forbidden per D-08) | Clean — 0 occurrences |
| `R/116_encounter_ses_index.R` | `return null / [] / {}` stubs | None — all branches return typed empty tibbles, not nulls, as correct fallbacks |
| `R/utils/utils_address.R` | `get_zip9_at_date` signature unchanged | VERIFIED — line 111 unchanged |
| `.needs_centroid_check` | Leaks to production output | Clean — only used as internal placeholder within `mutate()`, overwritten on every exit path |

---

### Human Verification Required

#### 1. Tier 3 runtime behavior on HiPerGator

**Test:** Stage `data/reference/zip5_centroid_zip9_crosswalk.csv` (once derivable via a licensed ZIP+4 source), then run `R/116_encounter_ses_index.R` and confirm `zip9_source == "zip5_centroid"` rows appear and `adi_natrank` populates for those rows.
**Expected:** Rows previously classified `zip5_no_zip9` migrate to `zip5_centroid`; `adi_natrank` remains NA until Neighborhood Atlas crosswalk is also staged (P-03a).
**Why human:** Requires HiPerGator, the ENCOUNTER DuckDB table, LDS_ADDRESS_HISTORY CSV, and a real centroid crosswalk file — none available locally.

#### 2. P1-02 regression test baseline constant

**Test:** On HiPerGator, before activating Tier 3, record `.baseline_n_zip9_resolved` from a run of `get_zip9_at_date() |> approximate_zip9()` on the sample fixture, then insert that constant into `test-utils-address-tier3.R` (currently left as a placeholder `_`).
**Expected:** With crosswalk absent, `sum(!is.na(out$ZIP9))` matches the recorded baseline exactly.
**Why human:** Requires the production address CSV and HiPerGator; the numeric constant cannot be determined statically.

---

### Gaps Summary

No gaps. All 8 observable truths are verified at the structural level. The two human-verification items above are prerequisite runtime validations that cannot proceed until the centroid crosswalk is derivable via a licensed ZIP+4 source (documented limitation, not a code defect).

---

_Verified: 2026-08-17_
_Verifier: Claude (gsd-verifier)_
