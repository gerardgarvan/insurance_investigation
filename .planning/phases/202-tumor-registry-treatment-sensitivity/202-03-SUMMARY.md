---
phase: 202
plan: 03
subsystem: smoke-test-registration
tags: [smoke_test, script_index, R88, registration, TRVAL-07]
dependency_graph:
  requires: [R/202_tr_sensitivity.R (202-01/02), R/88_smoke_test_comprehensive.R SECTION 15bd]
  provides: [R/88 SECTION 15be, R/SCRIPT_INDEX.md 202 entry]
  affects: [HiPerGator smoke run after R/202 is executed]
tech_stack:
  added: []
  patterns: [env-var-gated workbook checks, openxlsx::getSheetNames, skip-all loop]
key_files:
  created: []
  modified: [R/88_smoke_test_comprehensive.R, R/SCRIPT_INDEX.md]
decisions:
  - "SECTION 15be uses R202_SENSITIVITY_XLSX env-var gate; all 9 workbook checks skip when unset — consistent with Phase 201 15bd pattern"
  - "R/202 SCRIPT_INDEX entry placed after R/170 row (R/191 is last numbered entry; R/193 not yet indexed)"
metrics:
  duration: "5 min"
  completed: "2026-11-14"
  tasks_completed: 2
  files_created: 0
  files_modified: 2
---

# Phase 202 Plan 03: R/88 smoke section + SCRIPT_INDEX registration Summary

R/88 extended with SECTION 15be (Phase 202 TR sensitivity smoke checks) and R/202_tr_sensitivity.R registered in SCRIPT_INDEX.md. Both files parse cleanly.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Insert SECTION 15be into R/88; add TR-VAL-202 to SECTION 16 summary | 61063b3 |
| 2 | Register R/202_tr_sensitivity.R in SCRIPT_INDEX.md; final parse checks | 827533e |

## Deviations from Plan

**1. [Rule 1 - Placement] SCRIPT_INDEX entry inserted after R/170, not R/193**
- Found during: Task 2
- Issue: R/193_tr_lymphoma_flags_all_patients.R has no SCRIPT_INDEX entry yet, so there was no "after R/193" anchor. R/170 was the last row before the `---` separator.
- Fix: Inserted R/202 immediately after R/170 (which is physically the last table row). The entry still appears in the post-190 investigations block in numerical context.
- Files modified: R/SCRIPT_INDEX.md
- Commit: 827533e

## Known Stubs

None — this plan adds smoke infrastructure only. The underlying R/202_tr_sensitivity.R stubs (TR_IMMUNO_COLS, tr_flags_path placeholder) are tracked in 202-02-SUMMARY.md.

## Self-Check: PASSED

- R/88_smoke_test_comprehensive.R parse: PASSED (tools/rcheck.sh parse exits 0)
- R/202_tr_sensitivity.R parse: PASSED (tools/rcheck.sh parse exits 0)
- Commit 61063b3 (SECTION 15be): FOUND
- Commit 827533e (SCRIPT_INDEX): FOUND
- `grep -n "SECTION 15be" R/88_smoke_test_comprehensive.R`: 1 match at line 8144
- `grep -n "TR-VAL-202" R/88_smoke_test_comprehensive.R | wc -l`: 16 (>= 10)
- `grep -n "PPV_reverse" R/88_smoke_test_comprehensive.R`: 3 matches
- TR-VAL-202 summary message in SECTION 16: FOUND (line 8378)
- Section 15be before SECTION 16: CONFIRMED (8144 < 8220+)
- No list.files( in Section 15be: CONFIRMED
- R202_SENSITIVITY_XLSX env-var gate: CONFIRMED
- `grep -n "202_tr_sensitivity" R/SCRIPT_INDEX.md`: 1 match at line 189
- `grep -n "TRVAL-01" R/SCRIPT_INDEX.md`: 1 match
- `grep -n "R202_SENSITIVITY_XLSX" R/SCRIPT_INDEX.md`: 1 match

## Addendum — first HiPerGator run and follow-up (quick 261114-qv3, 2026-11-14)
- Run: denominator 600, footnote 121; HL TR rows UFH 432 / ORL 295 / TMH <11.
- Chemo: TR n 518; within 90d 241 (46.5%); not captured 276 (~155 no pipeline record, ~120 pipeline record >90d away). PPV_reverse 393 pipeline-chemo patients, 364 with TR chemo (92.6%).
- D_by_year chemo: <=2014 24.6% (61/248); >2014 71.1% (160/225); Unknown 44.4% (20/45). Points to EHR coverage window.
- Radiation: TR 138; not captured 109; captured-undated 26 (UFH, code-only); PPV 36.7%.
- Immunotherapy: PPV 6.8% (13/192). Definitional: registry codes brentuximab vedotin as chemotherapy; first course only.
- Follow-up changes: see `.planning/quick/261114-qv3-*/261114-qv3-SUMMARY.md` (three-tier not-captured split, sheet E_coverage_window, finer year bands, C consistency, labels/KEY, R/88 15be, helper + synthetic test).

## HiPerGator results (2026-11-14)

- Denominator 600; footnote 121. Chemo 46.5% within 90d overall; 80.3% (236/294) within coverage window.
- By dx year: <=2009 <11/115; 2010-12 27.8%; 2013-15 61.7%; 2016-18 68.2%; 2019+ 80.4%.
- Not captured (chemo): no pipeline record 154 / 22 in window; >90d after 110 / 23; >90d before 12.
- Radiation: 115 in window, <11 within 90d, 26 code-only, 84 no pipeline record (real gap).
- PPV: chemo 92.6%; radiation 36.7%; immunotherapy 6.8% (definitional).
- R/88 TR-VAL-202: 12/12 PASS. Phase complete.
