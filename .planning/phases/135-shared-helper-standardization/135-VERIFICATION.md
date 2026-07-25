---
phase: 135-shared-helper-standardization
verified: 2026-07-25T00:00:00Z
status: gaps_found
score: 26/27 must-haves verified
gaps:
  - truth: "R/23 grand-total Patient count is n_distinct(ID) across all codes, not sum of per-code patient counts"
    status: partial
    reason: "R/23 cannot use n_distinct(ID) because its input (Phase 39/40 pre-aggregated RDS) does not retain raw patient IDs. grand_total_patients variable was introduced with a PATTERN-A comment documenting the limitation, but the value is still sum(summary_df$n_patients). The underlying data architecture must be fixed upstream before this can be a true n_distinct."
    artifacts:
      - path: "R/23_combine_reports.R"
        issue: "Line 221: grand_total_patients <- sum(summary_df$n_patients) — comment says 'ideally n_distinct(ID)' but the actual value is still a sum of per-code counts. PATTERN-A not fully resolved for this file."
    missing:
      - "Phase 39/40 unmatched reports need to forward a deduplicated patient ID set so R/23 can compute true n_distinct(ID)"
      - "Track this as a pending upstream blocker in REQUIREMENTS.md or ROADMAP; PATTERN-A for R/23 should remain 'Partial' in the status table"
human_verification:
  - test: "Run R/88 SECTION 15aa in isolation on HiPerGator"
    expected: "All checks PASS, zero FAIL. Each pattern label (A through H) shows at least one PASS line."
    why_human: "R/88 loads R/00_config.R which connects to HiPerGator database; cannot run in CI or locally. The behavioral checks for is_cancer_code(), classify_doi_codes(), min_or_na() require R/utils to be sourced."
---

# Phase 135: Shared Helper Standardization — Verification Report

**Phase Goal:** Standardize shared helpers across the R pipeline — fix 7 cross-cutting code patterns (A through H, excluding E) identified in Phase 134's ingest integrity audit, add structural smoke tests to R/88 to guard against regression.
**Verified:** 2026-07-25
**Status:** gaps_found (1 partial gap + 1 human verification item)
**Re-verification:** No — initial verification.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `.normalize_code()` is the sole normalization entry point in utils_cancer.R, utils_doi.R, R/13, R/42 | VERIFIED | `R/utils/utils_cancer.R:49` defines `.normalize_code <- function(x) toupper(gsub("\\.", "", x, fixed = FALSE))`; called at lines 52 and 102. `utils_doi.R:102` calls `.normalize_code(codes)`. R/13 uses pre-computed `hl_icd10_clean`/`hl_icd9_clean` with OR expansion. R/42 hardcoded dotted keys all replaced. |
| 2 | R/40, R/43, R/44, R/46 use is_cancer_code() not `^[CD]` | VERIFIED | R/40:127, R/43:126, R/44:129, R/46:99 all use `filter(is_cancer_code(DX_norm))`. No `str_detect.*\^[CD]` pattern remains in any of the four files. |
| 3 | R/53 flags death-before-birth; R/14 uses min_or_na/max_or_na; R/31 uses min_or_na; R/93 uses coalesce for HAD_* | VERIFIED | R/53 SECTION 4C at line 198; R/14 lines 269-270 use `min_or_na`/`max_or_na`; R/31 lines 154-155 and 167-168 use `min_or_na`/`max_or_na`; R/93 lines 58, 67, 135 use `coalesce(HAD_CHEMO, 0L)`. |
| 4 | R/56 and R/57 define episode_count not encounter_count | VERIFIED | R/56:582 `summarise(episode_count = n(), ...)`, R/57:477 and 498 both `summarise(episode_count = n(), ...)`. No `encounter_count = n()` definition in either file. |
| 5 | R/62 grain comment corrected; R/67 n_total_encounters renamed n_total_dates | VERIFIED | R/62:15 header says `grain: patient x treatment_type x episode x date`. R/67 lines 191, 387, 450, 457 all use `n_total_dates`. PATTERN-H comment at line 380. |
| 6 | R/21 uses httr2 req_retry; R/27/R/105/R/108 is_transient includes 500/502 | VERIFIED | R/21:179 `httr2::req_retry(...)` with `c(429L, 500L, 502L, 503L, 504L)` in is_transient. R/27 lines 124/172/224, R/105 lines 141/176, R/108 line 181 all include 500L and 502L in is_transient. |
| 7 | R/21/R/22/R/50/R/98 config rewrite validates with parse() on tempfile before writing | VERIFIED | R/21:730-734, R/22:997-1001, R/50:648-652, R/98:305-319 all contain `tmp_verify <- tempfile(fileext = ".R")` followed by `parse_check <- tryCatch(parse(tmp_verify), ...)`. |
| 8 | R/23 grand-total Patient count is n_distinct(ID) | PARTIAL | `grand_total_patients` variable introduced with PATTERN-A comment at line 216-221, but the computed value is `sum(summary_df$n_patients)` — raw IDs are not available in R/23's pre-aggregated input. R/88 check passes because it only tests for `grand_total_patients` string presence, not that the value is truly deduplicated. |
| 9 | R/33 CODE-03 Patient_Count uses n_distinct(ID) per code | VERIFIED | Lines 274-276 use `n_distinct(sct_status_dx$ID[which(sct_status_dx$DX_norm == "Z9484")])` etc. |
| 10 | R/43 and R/44 TOTAL rows use n_distinct(ID) per category | VERIFIED | R/43:247 `grand_total_patients_43 <- n_distinct(dx_cancer$ID)`; R/44:249 equivalent. Both TOTAL tibbles use these values. |
| 11 | R/91 n_future_dates_after documented as all-table grand total | VERIFIED | Line 173-176: "PATTERN-A NOTE: n_future_dates_after is an all-table grand total" comment with verbatim "all-table grand total" phrase. |
| 12 | R/100 Sheet 1 patient totals de-duplicate to n_distinct(PATID) | VERIFIED | Line 234: `sheet1_grand_total_patients <- n_distinct(sheet1_base$PATID)`. |
| 13 | R/50 grand-total confirmed as n_distinct via patient_hits accumulator | VERIFIED | Line 563: `total_unique_patients <- n_distinct(category_patient_hits$ID)` with PATTERN-A confirmation comment at line 562. |
| 14 | R/88 has SECTION 15aa with checks for all 7 patterns (A-H excl E) | VERIFIED | R/88:4614 SECTION 15aa present. All seven pattern labels (A, B, C, D, F, G, H) appear in checks. PATTERN-A covers R/23, R/33, R/43, R/44, R/50, R/100. `.p135_check()` helper at line 4624. |
| 15 | REQUIREMENTS.md status table updated to reflect Phase 135 completion | FAILED | REQUIREMENTS.md lines 100-106 still show PATTERN-B, C, D, F, H as "Pending". Only PATTERN-A and PATTERN-G were already marked Complete before this phase. The status table was not updated post-execution. |

**Score:** 13/15 truths verified (1 partial, 1 tracking artifact)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/utils/utils_cancer.R` | `.normalize_code` helper; classify_codes / is_cancer_code use it | VERIFIED | Lines 49, 52, 102 |
| `R/utils/utils_doi.R` | classify_doi_codes uses .normalize_code() | VERIFIED | Line 102 |
| `R/13_survivorship_encounters.R` | HL DX filter accepts both dotted and undotted | VERIFIED | Lines 119-128 with OR expansion |
| `R/42_build_code_descriptions.R` | hardcoded dotted keys replaced (Z51.11 → Z5111) | VERIFIED | Lines 228-230; also Z5112, V5811, V5812, Z510 |
| `R/40_cancer_site_frequency.R` | filter uses is_cancer_code() | VERIFIED | Line 127 |
| `R/43_cancer_site_confirmation.R` | filter uses is_cancer_code(); TOTAL uses n_distinct | VERIFIED | Lines 126, 247 |
| `R/44_cancer_site_confirmation_7day.R` | filter uses is_cancer_code(); TOTAL uses n_distinct | VERIFIED | Lines 129, 249 |
| `R/46_cancer_summary_table.R` | filter uses is_cancer_code() | VERIFIED | Line 99 |
| `R/53_death_date_validation.R` | SECTION 4C death-before-birth block | VERIFIED | Lines 198-239, 559 |
| `R/14_build_cohort.R` | min_or_na / max_or_na for ENR dates | VERIFIED | Lines 269-270 |
| `R/31_pre_diagnosis_treatments.R` | min_or_na in episode_start summarise | VERIFIED | Lines 154-155, 167-168 |
| `R/93_no_treatment_medicaid.R` | coalesce(HAD_*, 0L) in filters | VERIFIED | Lines 58, 67, 135 |
| `R/56_new_tables_from_groupings.R` | episode_count not encounter_count | VERIFIED | Lines 582-583 |
| `R/57_explore_dx_deduplication.R` | episode_count not encounter_count | VERIFIED | Lines 477, 498 |
| `R/62_tiered_date_level.R` | grain comment corrected | VERIFIED | Line 15 |
| `R/67_multi_source_overlap_detection.R` | n_total_dates not n_total_encounters | VERIFIED | Lines 191, 387, 450, 457 |
| `R/21_investigate_unmatched.R` | httr2 req_retry; PATTERN-F verify-before-write | VERIFIED | Lines 177-185 (retry), 730-734 (verify) |
| `R/22_investigate_unmatched_ndc.R` | PATTERN-F verify-before-write | VERIFIED | Lines 997-1001 |
| `R/50_all_codes_resolved.R` | PATTERN-F verify-before-write; n_distinct patient total | VERIFIED | Lines 648-652 (verify), 563 (n_distinct) |
| `R/98_radiation_cpt_audit.R` | PATTERN-F verify-before-write | VERIFIED | Lines 305-319 |
| `R/27_drug_name_resolution.R` | is_transient includes 500/502 | VERIFIED | Lines 124, 172, 224 |
| `R/105_normalize_supportive_care_meaning.R` | is_transient includes 500/502 | VERIFIED | Lines 141, 176 |
| `R/108_build_ndc_rxnorm_crosswalk.R` | is_transient includes 500/502 | VERIFIED | Line 181 |
| `R/23_combine_reports.R` | grand total uses n_distinct(ID) | PARTIAL | `grand_total_patients` variable with PATTERN-A comment, but value is still `sum(summary_df$n_patients)` — structural upstream constraint |
| `R/33_code_verification.R` | Patient_Count uses n_distinct(ID) per code | VERIFIED | Lines 274-276 |
| `R/91_data_quality_summary.R` | all-table grand total comment | VERIFIED | Lines 173-176 |
| `R/100_ruca_rurality_summary.R` | n_distinct(PATID) for Sheet 1 | VERIFIED | Line 234 |
| `R/88_smoke_test_comprehensive.R` | SECTION 15aa: pattern-regression checks for A-H | VERIFIED | Lines 4614-4779 |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| R/utils/utils_cancer.R | .normalize_code | call in classify_codes() and is_cancer_code() | WIRED | Lines 52, 102 |
| R/utils/utils_doi.R | .normalize_code | call in classify_doi_codes() | WIRED | Line 102 |
| R/40/43/44/46 neoplasm filter | is_cancer_code() in utils_cancer.R | function call replacing str_detect | WIRED | Confirmed in all four files |
| R/21 lookup_hcpcs_batch | httr2::req_retry | replace httr GET with httr2 pipeline | WIRED | Lines 177-185; no `httr::GET(url,` found in function body |
| R/21/R/22/R/50/R/98 config rewrite | parse() verify before writeLines() | tryCatch wrapping write step | WIRED | All four files contain `tmp_verify` tempfile pattern |
| R/88 SECTION 15aa | utils_cancer.R .normalize_code, is_cancer_code | direct function calls with known inputs | WIRED | Lines 4638-4659 |
| R/88 SECTION 15aa | R/21/R/22/R/50/R/98 source files | grep check for verify-before-write | WIRED | Lines 4699-4710 |

---

### Data-Flow Trace (Level 4)

Not applicable — all artifacts are R script analysis/reporting tools, not web components rendering dynamic data from an API. The relevant data flows (API calls, database queries) were verified at Level 3 (wiring).

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — scripts require HiPerGator database connection and renv environment to source. R/88 SECTION 15aa is the canonical spot-check mechanism; human execution is required (see Human Verification Required section).

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| PATTERN-A | 135-05 | De-duplicate to n_distinct(ID) before totaling in R/23, R/33, R/43, R/44, R/50, R/91, R/100 | PARTIAL | 6 of 7 files fully fixed; R/23 is structurally constrained — documents the gap but cannot implement true n_distinct without upstream changes |
| PATTERN-B | 135-01 | Single shared code-normalization convention (strip all dots + toupper) | SATISFIED | .normalize_code() in utils_cancer.R used by utils_doi.R, R/13, R/42 |
| PATTERN-C | 135-02 | Neoplasm filters use is_cancer_code() not ^[CD] | SATISFIED | All four files (R/40, R/43, R/44, R/46) confirmed |
| PATTERN-D | 135-06 | API retry for transient errors; httr2 with 429/500/502/503/504 set | SATISFIED | R/21 uses httr2 req_retry; R/27/R/105/R/108 extended to 500/502 |
| PATTERN-F | 135-06 | Config rewrite validates parse() on tempfile before writing | SATISFIED | All four rewriters (R/21, R/22, R/50, R/98) have tmp_verify pattern |
| PATTERN-G | 135-03 | NA-safe guards: death-before-birth in R/53; min_or_na in R/14/R/31; coalesce in R/93 | SATISFIED | All four files confirmed |
| PATTERN-H | 135-04 | Grain-mislabeled columns renamed: R/56/R/57 episode_count; R/62 grain comment; R/67 n_total_dates | SATISFIED | All four files confirmed |

**Orphaned requirements check:** REQUIREMENTS.md maps PATTERN-B, C, D, F, H to Phase 135 but still shows these as "Pending" in the status table. The code changes are complete; the tracking document was not updated post-execution. This is a documentation gap, not a code gap.

---

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| R/23_combine_reports.R | `grand_total_patients <- sum(summary_df$n_patients)` with comment saying "ideally n_distinct(ID)" | Warning | PATTERN-A not fully resolved for R/23; grand total may overcount patients spanning multiple classifications. Acknowledged in SUMMARY as a structural constraint requiring upstream fix. Not a regression — this is the same value as before, now with explicit documentation. |
| REQUIREMENTS.md | PATTERN-B, C, D, F, H still marked "Pending" in status table | Info | Tracking artifact only; actual code changes are complete. Should be updated to "Complete" for Phase 135. |

---

### Human Verification Required

#### 1. R/88 SECTION 15aa Execution on HiPerGator

**Test:** Source R/00_config.R then evaluate SECTION 15aa of R/88_smoke_test_comprehensive.R. The bounded invocation from the plan is:
```r
lines <- readLines('R/88_smoke_test_comprehensive.R')
start <- grep('SECTION 15aa', lines)[1]
rest  <- grep('^# ===', lines); end <- rest[rest > start][2] - 1
source('R/00_config.R')
eval(parse(text = paste(lines[start:end], collapse = '\n')))
```
**Expected:** Output shows `Section 15aa: 26 PASS, 0 FAIL` (or similar count — zero FAIL lines). All pattern labels (A through H, excl E) appear with PASS.
**Why human:** R/00_config.R requires a live HiPerGator DuckDB connection. The behavioral checks for is_cancer_code(), classify_doi_codes(), and min_or_na() require the sourced utils to be available. Cannot run in a local or CI environment.

---

### Gaps Summary

**1 gap (partial) — PATTERN-A in R/23 (structural constraint):**

R/23_combine_reports.R was designed to consume pre-aggregated RDS output from Phase 39/40 unmatched reports. These RDS files carry only `n_patients` per code, not raw patient IDs. The plan's intended fix (`n_distinct(df$ID)`) cannot be applied without changing what Phase 39/40 outputs. The code was updated to introduce a `grand_total_patients` variable with an explicit PATTERN-A comment documenting the limitation and the upstream fix path. The R/88 smoke test check for R/23 passes (it looks for `grand_total_patients` string presence), but the actual total in the XLSX output remains `sum(summary_df$n_patients)`.

This is a documented deferral to a future phase (Phase 39 or 40 rework), not a regression. The PATTERN-A requirement as stated in REQUIREMENTS.md includes R/23 — so PATTERN-A cannot be marked "Complete" for R/23 specifically until the upstream fix is in place.

**1 tracking gap — REQUIREMENTS.md status table:**

Lines 100-106 of REQUIREMENTS.md still mark PATTERN-B, C, D, F, H as "Pending". These should be updated to "Complete" for Phase 135 to reflect that all code changes have been made.

---

_Verified: 2026-07-25_
_Verifier: Claude (gsd-verifier)_
