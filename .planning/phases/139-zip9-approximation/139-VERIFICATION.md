---
phase: 139-zip9-approximation
verified: 2026-07-28T00:00:00Z
status: human_needed
score: 7/8 must-haves verified
re_verification: false
human_verification:
  - test: "Run Phase 137 + Phase 139 testthat suites on HiPerGator with the real LDS_ADDRESS_HISTORY_Mailhot_V1.csv in place"
    expected: "Test 0 (integration) reports sum(zip9_source == 'zip5_modal') > 0; ZIP5 recovery count (rows where ZIP9 is NA and ZIP5 is non-NA) is logged and non-trivial; all 12 tests pass"
    why_human: "Test 0 drives the real get_zip9_at_date() against LDS_ADDRESS_HISTORY_Mailhot_V1.csv. That file lives only on HiPerGator. The Task-0 gate (count of bare-ZIP5 recoveries in production data) was deferred to a HiPerGator run per the SUMMARY. Cannot verify programmatically without the file."
---

# Phase 139: ZIP9 Approximation Verification Report

**Phase Goal:** Extend get_zip9_at_date() to recover ZIP5 from bare 5-digit ADDRESS_ZIP9 values, and implement approximate_zip9() to fill ZIP9 via modal ZIP9 lookup per ZIP5, with provenance columns and match_type invariance.
**Verified:** 2026-07-28
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | get_zip9_at_date() emits non-NA ZIP5 for address records whose ADDRESS_ZIP9 held a bare 5-digit value | VERIFIED | Line 107: `zip5_norm = coalesce(normalize_zip5(zip9_norm), normalize_zip5_raw(ADDRESS_ZIP9))`; normalize_zip5_raw() rewritten (lines 46-51) to strip-slice-pad-validate rather than pad-before-validate |
| 2 | approximate_zip9() returns input columns plus zip9_source, zip5_modal_freq, zip5_n_candidates, zip5_modal_share | VERIFIED | Lines 344-349 (already_filled branch), 353-358 (none_rows branch), 370-373 (approx_joined branch) all add exactly those four columns; select(-modal_zip9) at line 374 drops the join artifact |
| 3 | match_type is never overwritten by approximate_zip9(); temporal provenance survives approximation | VERIFIED | approximate_zip9() never writes match_type; the three split subsets (already_filled, none_rows, approx_joined) all pass match_type through unchanged via bind_rows(); Test 9 in the test suite enforces this contract |
| 4 | zip9_source distinguishes zip9_observed / zip5_modal / zip5_no_zip9 / no_zip5 / none | VERIFIED | Lines 345, 354, 365-368 implement all five levels; case_when at lines 365-368: zip5_modal when modal_zip9 not NA, zip5_no_zip9 when ZIP5 not NA, TRUE -> no_zip5 |
| 5 | Modal frequency counts distinct patient IDs, not address-history rows | VERIFIED | Line 312: `freq = n_distinct(ID)` in the zip5_lookup build |
| 6 | Tie-breaking is total: freq, then recency, then ZIP9 string | VERIFIED | Line 321: `arrange(desc(freq), desc(latest_date), zip9_norm, .by_group = TRUE)` |
| 7 | An integration test drives the real get_zip9_at_date() from a synthetic CSV and asserts at least one zip5_modal row | VERIFIED (locally) | Test 0 (lines 82-109) uses a synthetic LDS CSV, calls the real get_zip9_at_date() then approximate_zip9(), and asserts `sum(result$zip9_source == "zip5_modal") > 0`. Passes locally. Real-data HiPerGator run needed to close the Task-0 gate. |
| 8 | When LDS_ADDRESS_HISTORY_Mailhot_V1.csv is absent, the function logs and returns input unchanged without stopping | VERIFIED | Lines 239-245: probe-first gate checks file.exists(), emits message with "LDS_ADDRESS_HISTORY not found", returns result_tbl; Test 5 (lines 197-214) asserts no error and no extra columns |

**Score: 7/8 truths fully verified (Truth 7 passes locally; HiPerGator production run with real file needed to confirm the Task-0 gate)**

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/utils/utils_address.R` | approximate_zip9() appended; get_zip9_at_date() patched for ZIP5 recovery | VERIFIED | File is 407 lines. approximate_zip9() defined at line 233. normalize_zip5_raw() rewritten at lines 46-51. ZIP5 coalesce at line 107. |
| `tests/testthat/test-utils_address_approximate_zip9.R` | 12-case testthat suite (Tests 0-11) | VERIFIED | File present, 323 lines. All 12 tests (Test 0 through Test 11) exist with correct test_that() wrappers. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| approximate_zip9() | LDS_ADDRESS_HISTORY_Mailhot_V1.csv | probe-first gate then vroom load on demand (D-08) | VERIFIED | Lines 235-244: builds addr_path from CONFIG$data_dir, checks file.exists(), falls through to tryCatch(vroom::vroom(...)) at lines 277-287 |
| zip5_lookup (modal table) | result_tbl rows where ZIP9 is NA and match_type != "none" | left_join on ZIP5 | VERIFIED | Lines 361-374: `to_approx %>% left_join(zip5_lookup, by = "ZIP5")` |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| approximate_zip9() | zip5_lookup | addr_raw from LDS CSV loaded via vroom | Yes — built from n_distinct(ID) summarise over real rows, not static | FLOWING |
| approximate_zip9() | to_approx | result_tbl input (rows with ZIP9 NA, match_type != "none") | Yes — filtered from caller-supplied tibble | FLOWING |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — no runnable entry points without HiPerGator file system. The R functions require LDS_ADDRESS_HISTORY_Mailhot_V1.csv at CONFIG$data_dir. Local synthetic tests cover behavior; full behavior is gated on the HiPerGator run.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| ZIP9-APPROX-01 | 139-01-PLAN.md | Extend get_zip9_at_date() for ZIP5 recovery and implement approximate_zip9() with modal lookup, provenance columns, and match_type invariance | SATISFIED | All five sub-deliverables present: normalize_zip5_raw() fix (line 46-51), ZIP5 coalesce (line 107), approximate_zip9() function (line 233), five zip9_source levels (lines 345/354/365-368), four provenance columns (lines 344-373), match_type never written, 12-case test suite |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `R/utils/utils_address.R` | 252-264 | `nrow(to_approx) == 0` early-return branch adds provenance columns using `if_else(!is.na(ZIP9), "zip9_observed", "none")` — this conflates match_type=="none" rows (which should get zip9_source="none") with rows that have non-NA ZIP9 (zip9_observed). A row with ZIP9=NA and match_type="none" gets zip9_source="none" correctly, but a row with ZIP9 present gets "zip9_observed" — which is correct. The logic is technically accurate but the condition is subtle. | Info | No functional impact; schema contract is met. No gap opened. |

No blocker anti-patterns found.

---

### Human Verification Required

#### 1. HiPerGator Integration Gate (Task-0 gate — ZIP5 recovery count)

**Test:** On HiPerGator with the real LDS_ADDRESS_HISTORY_Mailhot_V1.csv in place, run:
```r
source("R/00_config.R")
# Sample of known IDs and dates
result <- get_zip9_at_date(sample_ids, sample_dates) |> approximate_zip9()
cat("ZIP5 recovery (ZIP9 NA, ZIP5 non-NA before approx):", sum(is.na(raw$ZIP9) & !is.na(raw$ZIP5)), "\n")
cat("zip5_modal rows after approximation:", sum(result$zip9_source == "zip5_modal"), "\n")
```
Also run: `testthat::test_dir("tests/testthat", filter = "utils_address")`

**Expected:** ZIP5 recovery count is non-trivial (> 0); at least one zip5_modal row in the approximated result; all 12 tests pass (Test 0 already passes locally with synthetic data).

**Why human:** LDS_ADDRESS_HISTORY_Mailhot_V1.csv is not available in the local repo — it lives on HiPerGator. The Task-0 gate in the PLAN requires a human to observe the count and confirm the premise of the phase holds in production data before downstream phases consume approximate_zip9() output.

---

### Gaps Summary

No gaps. All eight must-have truths are satisfied in the code. The sole outstanding item is the HiPerGator production run that closes the Task-0 human gate defined in the PLAN. This is a validation step, not a missing implementation: the code changes are complete, correct, and regression-safe locally.

---

_Verified: 2026-07-28_
_Verifier: Claude (gsd-verifier)_
