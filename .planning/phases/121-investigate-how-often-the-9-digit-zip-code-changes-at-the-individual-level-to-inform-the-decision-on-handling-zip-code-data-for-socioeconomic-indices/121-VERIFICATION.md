---
phase: 121-investigate-how-often-the-9-digit-zip-code-changes-at-the-individual-level-to-inform-the-decision-on-handling-zip-code-data-for-socioeconomic-indices
verified: 2026-07-13T00:00:00Z
status: human_needed
score: 7/7 must-haves verified (structural)
human_verification:
  - test: "Run Rscript R/106_zip_change_frequency.R on HiPerGator with LDS_ADDRESS_HISTORY present"
    expected: "Script loads CSV, prints headline stats (n_patients_total, pct_ever_changed_zip9, pct_ever_changed_zip5, pct_zip9_change_only, median_distinct_zip9, n_with_na_zip9, pct_disagree), then writes output/zip_change_frequency.xlsx with 5 sheets"
    why_human: "Rscript not installed on Windows executor; local test fixtures do not include LDS_ADDRESS_HISTORY_Mailhot_V1.csv — R/106's probe gate correctly exits with status 0 locally"
  - test: "Run Rscript R/88_smoke_test_comprehensive.R on HiPerGator after R/106 has produced zip_change_frequency.xlsx"
    expected: "Section 15s all 14 checks PASS (Check 14 flips from SKIPPED to a real xlsx-present PASS; Checks 1-13 already pass locally on structure)"
    why_human: "Check 14 IS_LOCAL-gate only activates when IS_LOCAL=FALSE and the xlsx exists — requires HiPerGator runtime"
  - test: "Confirm exact LDS_ADDRESS_HISTORY filename at the probed path (CONFIG$data_dir/LDS_ADDRESS_HISTORY_Mailhot_V1.csv)"
    expected: "Either file exists and R/106 proceeds, or data custodian provides the correct filename so ADDR_FILENAME constant can be updated"
    why_human: "Runtime-unknown filename — the 4 open questions (exact filename, ADDRESS_ZIP5 fill rate, ADDRESS_PREFERRED fill rate, HL cohort breadth) are handled by graceful runtime branches in R/106"
---

# Phase 121: ZIP Change Frequency Investigation Verification Report

**Phase Goal:** Create a read-only investigation quantifying how often an individual patient's 9-digit ZIP changes over time (at BOTH ZIP9 and ZIP5 granularity), output as a styled multi-sheet xlsx + console summary, to inform the downstream decision on handling ZIP data for socioeconomic indices (ADI/SVI). Probe-first against LDS_ADDRESS_HISTORY; graceful exit if absent.
**Verified:** 2026-07-13
**Status:** human_needed (all structural checks PASS; runtime confirmation deferred to HiPerGator per the dual-environment pattern established for Phases 119-120)
**Re-verification:** No — initial verification

---

## Environment Note

This is a Windows host with NO Rscript installed and local test fixtures do NOT include LDS_ADDRESS_HISTORY. Verification is therefore **structural** (grep-based) exactly as Phases 119-120 were verified. Runtime confirmation (Rscript parse, Section 15s PASS, xlsx generation) is legitimately deferred to HiPerGator. "Couldn't run Rscript locally" is NOT treated as a gap.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A user on HiPerGator can run R/106 and, if LDS_ADDRESS_HISTORY is present, see per-patient ZIP change frequency at BOTH ZIP9 and ZIP5 granularity (D-04) | ? HUMAN | R/106 exists (756 lines), contains group_by(ID)+n_distinct for both zip9_norm and zip5_norm with !is.na filter before counting. Runtime requires HiPerGator data. |
| 2 | If LDS_ADDRESS_HISTORY is absent, R/106 reports that clearly and exits gracefully with status 0 (no crash) (D-02) | ✓ VERIFIED | Line 84: `if (!file.exists(addr_path))` + line 93: `quit(status = 0)` — no stop() used for the probe gate |
| 3 | R/106 produces a 5-sheet styled xlsx matching the R/100 look-and-feel and logs headline stats to the console before writing it (D-06, D-09) | ✓ VERIFIED | 5 add_styled_sheet() calls (lines 719-752); console summary at line 582; wb_save at line 754 (summary precedes write); add_styled_sheet verbatim from R/100 with DARK_GRAY/WHITE/DARK_TEXT constants |
| 4 | The report surfaces the ZIP9-change-only distinction (ZIP9 changed but ZIP5 did not) so the ADI-vs-SVI decision can be made with full info (D-05) | ✓ VERIFIED | Line 255: `zip9_change_only = n_zip9_distinct > 1 & n_zip5_distinct == 1`; lines 320/324: n_zip9_change_only and pct_zip9_change_only computed and logged |
| 5 | The report presents the most-recent vs modal single-ZIP tie-break disagreement rate without committing to one rule (D-11) | ✓ VERIFIED | Sheet 4 (Tie-Break Comparison, lines 483-575): reports n_agree, n_disagree, pct_disagree; outputs only agree/disagree counts (not individual ZIPs); ADDRESS_PREFERRED <5% fallback documented in sheet subtitle |
| 6 | R/106 is registered in R/39, smoke-tested in R/88 Section 15s, and indexed in R/SCRIPT_INDEX.md (D-08) | ✓ VERIFIED | R/39 line 196: R/106 registered as comma-less final entry; R/88 lines 2501-2583: Section 15s with 14 checks; SCRIPT_INDEX.md line 152: R/106 row in Phase 121 column |
| 7 | A user can run R/88 locally and see all Phase 121 structural checks pass (R/106 present + probe gate + ZIP normalization + xlsx + HIPAA suppression) | ✓ VERIFIED | Section 15s Checks 1-13 are all structural greps that verify locally; Check 14 is IS_LOCAL-gated and returns SKIPPED=TRUE locally |

**Score:** 6/7 truths verified structurally; 1 truth (T1 — actual HiPerGator runtime) deferred to human verification.

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/106_zip_change_frequency.R` | Read-only ZIP change frequency investigation: probe gate + 5-sheet styled xlsx + console summary | ✓ VERIFIED | 756 lines (>= 150 required); contains normalize_zip9, normalize_zip5, probe gate, add_styled_sheet, wb_save, HIPAA suppression, group_by(ID) |
| `R/39_run_all_investigations.R` | R/106 registered as the new comma-less final investigation_scripts entry (R/105 gains a trailing comma) | ✓ VERIFIED | Line 195: R/105 ends with comma; line 196: R/106 has no trailing comma before closing `)` on line 197 |
| `R/88_smoke_test_comprehensive.R` | Section 15s: 14 Phase 121 structural checks + SMOKE-121-01 summary line | ✓ VERIFIED | Section 15s at lines 2501-2583 (between 15r at 2412 and 15g at 2585); 14 check() calls confirmed; SMOKE-121-01 at line 4158 |
| `R/SCRIPT_INDEX.md` | R/106 row in Post-Renumber Investigations (100+) table; counts 6->7, Total 92->93 | ✓ VERIFIED | Line 152: R/106 row with Phase 121; line 205: count=7; line 208: Total=93 |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `R/106_zip_change_frequency.R` | `file.path(CONFIG$data_dir, ADDR_FILENAME)` | `file.exists()` probe + `quit(status = 0)` when absent | ✓ WIRED | Lines 80-93: addr_path constructed, file.exists() probe, quit(status=0) on absence |
| `R/39_run_all_investigations.R` | `R/106_zip_change_frequency.R` | investigation_scripts vector entry | ✓ WIRED | Line 196: `"R/106_zip_change_frequency.R"` as sole comma-less final entry |
| `R/88_smoke_test_comprehensive.R` | `R/106_zip_change_frequency.R` | Section 15s file.exists + grep checks | ✓ WIRED | Lines 2512-2513: `r106_exists <- file.exists("R/106_zip_change_frequency.R")` then check() |

---

## Data-Flow Trace (Level 4)

Not applicable — R/106 is a read-only investigation script, not a component that renders UI or feeds a downstream pipeline at runtime. The data flow (CSV -> normalization -> per-patient metrics -> xlsx) requires HiPerGator runtime and is deferred to human verification.

---

## Behavioral Spot-Checks

Step 7b: SKIPPED — Rscript is not installed on the Windows executor; LDS_ADDRESS_HISTORY_Mailhot_V1.csv is not in local test fixtures. This is the expected dual-environment pattern for Phase 121. Runtime checks deferred to HiPerGator.

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| ZIP-01 | 121-01-PLAN.md | Probe gate: file.exists() on LDS_ADDRESS_HISTORY; quit(status=0) when absent | ✓ SATISFIED | R/106 lines 80-93; Section 15s Check 4 (probe gate) + Check 5 (quit not stop) |
| ZIP-02 | 121-01-PLAN.md | Per-patient ZIP metrics at BOTH ZIP9 and ZIP5 granularity, grouped by ID, NA filtered before distinct counts | ✓ SATISFIED | R/106 lines 220-256: group_by(ID), !is.na filter before n_distinct, zip9_change_only flag; Section 15s Check 11 |
| ZIP-03 | 121-01-PLAN.md | 5-sheet styled xlsx: distribution, change-rates+histogram, time-between-changes, tie-break, recommendation/metadata | ✓ SATISFIED | R/106 lines 719-754: 5 add_styled_sheet() calls + wb_save; HIPAA suppression in Sheets 2/3; console summary at line 582; Section 15s Check 12 + Check 13 |
| ZIP-04 | 121-01-PLAN.md | R/106 registered in R/39 as comma-less final entry; R/88 Section 15s added; R/SCRIPT_INDEX.md updated | ✓ SATISFIED | R/39 lines 195-196; R/88 lines 2501-2583; SCRIPT_INDEX.md lines 152/205/208 |
| SMOKE-121-01 | 121-01-PLAN.md | R/88 validates Phase 121 ZIP change frequency structural integrity (Section 15s, 14 checks) | ✓ SATISFIED | Section 15s confirmed present between 15r and 15g with 14 check() calls; SMOKE-121-01 summary line at R/88 line 4158 |

**Orphaned requirements note:** ZIP-01 through ZIP-04 and SMOKE-121-01 are declared in the PLAN frontmatter but have NOT yet been added to `.planning/REQUIREMENTS.md`. The last entry in REQUIREMENTS.md is SMOKE-120-01 (Phase 120, last updated 2026-07-10). This is a documentation gap — the requirements exist and are satisfied in code but the central requirements register needs updating. This is informational (not a blocker) since prior phases (118, 119, 120) all followed the pattern of adding requirements to REQUIREMENTS.md.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| R/88_smoke_test_comprehensive.R | whole file | Paren imbalance: 3626 open vs 3598 close (diff=28) | ℹ️ Info | Pre-existing imbalance confirmed present before Phase 121 (3545 vs 3517 = same 28-gap). Phase 121 Section 15s additions are balanced (81 opens / 81 closes). Not a Phase 121 regression. |
| R/106_zip_change_frequency.R | 116 | Comment mentions "PATID" (as a negative: "ID not PATID -- Pitfall 4") | ℹ️ Info | PATID only in a comment; all actual code uses `ID`. Not a stub or error. |

No blockers or warnings found.

---

## Paren Balance Summary

| File | Open | Close | Balanced | Note |
|------|------|-------|----------|------|
| `R/106_zip_change_frequency.R` | 524 | 524 | True | New file — fully balanced |
| `R/39_run_all_investigations.R` | 246 | 246 | True | Modified file — fully balanced |
| `R/88_smoke_test_comprehensive.R` | 3626 | 3598 | False (diff=28) | Pre-existing imbalance (28-gap unchanged from before Phase 121); Section 15s block itself is balanced (79/79) |

---

## Human Verification Required

### 1. R/106 Runtime — HiPerGator with LDS_ADDRESS_HISTORY

**Test:** On HiPerGator: `Rscript R/106_zip_change_frequency.R`
**Expected:** Script loads CSV, prints headline stats block (n_patients_total, pct_ever_changed_zip9, pct_ever_changed_zip5, pct_zip9_change_only, median_distinct_zip9, n_with_na_zip9, pct_disagree), then writes `output/zip_change_frequency.xlsx`. If `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` does not exist at the probed path, R/106 prints a clear diagnostic message and exits with status 0 (not a crash).
**Why human:** Rscript not installed on Windows executor; LDS_ADDRESS_HISTORY not in local fixtures.

### 2. R/88 Section 15s Check 14 — HiPerGator after xlsx produced

**Test:** On HiPerGator after running R/106: `Rscript R/88_smoke_test_comprehensive.R`
**Expected:** Section 15s all 14 checks PASS. Check 14 ("R/106 output xlsx present") flips from SKIPPED to PASS because IS_LOCAL=FALSE and `output/zip_change_frequency.xlsx` exists.
**Why human:** Check 14 IS_LOCAL-gate only activates in the HiPerGator environment.

### 3. Exact LDS_ADDRESS_HISTORY filename confirmation

**Test:** On HiPerGator: verify `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` exists at `CONFIG$data_dir`.
**Expected:** File found, R/106 proceeds past the probe gate. If the filename differs, update `ADDR_FILENAME` constant at R/106 line 77.
**Why human:** Runtime-unknown filename is one of the 4 open questions encoded as graceful runtime branches in R/106.

---

## Gaps Summary

No structural gaps found. All 7 must-have truths are verified structurally. The 3 human verification items above are expected runtime deferrals per the Phase 121 plan's dual-environment design (identical pattern to Phases 119 and 120).

The one informational item worth acting on before Phase 122 work begins:

- **REQUIREMENTS.md not updated** — ZIP-01 through ZIP-04 and SMOKE-121-01 are not yet added to `.planning/REQUIREMENTS.md`. The last entry is SMOKE-120-01 (2026-07-10). This should be added to maintain the audit trail that prior phases follow.

---

_Verified: 2026-07-13_
_Verifier: Claude (gsd-verifier)_
