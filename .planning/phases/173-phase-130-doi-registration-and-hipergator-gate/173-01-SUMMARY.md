---
phase: 173-phase-130-doi-registration-and-hipergator-gate
plan: 01
subsystem: doi-registration-closeout
tags: [doi, r88, r39, script-index, smoke-test, hipergator-gate]
requirements: [DOI-REG-01, DOI-REG-02, DOI-REG-03]
dependency-graph:
  requires: [Phase 130 code artifacts (130-01-SUMMARY.md, 130-02-SUMMARY.md), pcornet.duckdb (real DIAGNOSIS data on HiPerGator), treatment_episode_detail.rds]
  provides: [DOI-REG-01 closed, DOI-REG-02 closed, DOI-REG-03 closed]
  affects: [R/39, R/SCRIPT_INDEX.md, R/88, doi_encounters.rds, doi_patients.rds, doi_attribution_report.xlsx]
tech-stack:
  added: []
  patterns: [IS_LOCAL-gated HiPerGator runtime checks in R/88, Path B re-run strategy, unrelated R/88 IMMU fix bd94062]
key-files:
  created: []
  modified: [R/39_run_all_investigations.R (verified intact), R/SCRIPT_INDEX.md (verified intact), R/88_smoke_test_comprehensive.R (IMMU fix bd94062 unrelated)]
decisions:
  - "Path B chosen (fresh HiPerGator re-run) — DuckDB date not checked; treatment_episode_detail.rds may have been refreshed by Phase 164, but DoI counts matched Phase 130 baseline exactly confirming DuckDB unchanged"
  - "R/88 IMMU fix (bd94062) is unrelated and non-blocking — replaced stale is_sct_conditioning_context filter (removed Phase 99) with absence checks in Checks 13-15"
metrics:
  duration: "~0.2 minutes (R/4.5 interactive on HiPerGator, host c0700a-s28.ufhpc)"
  completed: "2026-10-12"
  tasks: 4
  files: 0
requirements-completed: [DOI-REG-01, DOI-REG-02, DOI-REG-03]
---

# Phase 173 Plan 01: DoI Registration Close-out Summary

**One-liner:** Phase 130 DoI layer (R/111 + R/112) confirmed registered and runtime-verified on HiPerGator — 920 R/88 checks passed, SMOKE-130-01 confirmed, encounter-grain DoI counts exactly match the 2026-07-16 baseline (DuckDB unchanged).

---

## Task 1: Code Intact Evidence (DOI-REG-01 / DOI-REG-02)

| # | Check | Evidence (line / matched text) | PASS/FAIL |
|---|-------|-------------------------------|-----------|
| 1 | R/39 contains `R/111_doi_classification.R` | L217: `"R/111_doi_classification.R"` | PASS |
| 2 | R/39 contains `R/112_doi_attribution_report.R` | L218: `"R/112_doi_attribution_report.R"` | PASS |
| 3 | R/39: R/111 line < R/112 line (dependency order) | L217 < L218 | PASS |
| 4 | R/39: `doi_attribution_report.xlsx` in expected_xlsx | L336: `"doi_attribution_report.xlsx"` | PASS |
| 5 | SCRIPT_INDEX.md: R/111 row present | L157: DoI classification producer; mentions `DOI_CODE_MAP`, `doi_encounters.rds`, `doi_patients.rds` | PASS |
| 6 | SCRIPT_INDEX.md: R/112 row present | L158: DoI attribution report producer; mentions `doi_attribution_report.xlsx`, 4-sheet xlsx | PASS |
| 7 | SCRIPT_INDEX.md: `R/111_doi_attribution_report` absent (correct name is R/112) | Grep across R/ returns 0 matches in R/ source files | PASS |
| 8 | R/88: `SECTION 15w` present | `# SECTION 15w: DIAGNOSIS-OF-INTEREST (DoI) LAYER VALIDATION (Phase 130)` confirmed | PASS |
| 9 | R/88: `intersect(names(DOI_CODE_MAP)` present | `doi_cancer_overlap <- intersect(names(DOI_CODE_MAP), cancer_keys)` confirmed | PASS |
| 10 | R/88: exactly one `SMOKE-130-01` footer line | `message("  * SMOKE-130-01: R/88 validates Phase 130 DoI layer ...")` — single match | PASS |
| 11 | R/88: IS_LOCAL-gated runtime checks (Checks 12-14) | Check 12 (`!IS_LOCAL && file.exists(enc_rds) && file.exists(pat_rds)`), Check 13 (`!IS_LOCAL && file.exists(doi_xlsx)`), Check 14 (`!IS_LOCAL && file.exists(enc_rds)`) — all three gated | PASS |

**Overall: 11/11 PASS — code fully intact.**

---

## Task 2: Path Decision

**Path B was taken.** The user elected to run R/111 and R/112 fresh on HiPerGator rather than cite the 2026-07-16 Phase 130 cached artifacts.

**DuckDB date:** Not checked before running. `pcornet.duckdb` was presumed stable — confirmed post-hoc by exact count match against the July baseline (see Task 3).

**treatment_episode_detail.rds:** May have been refreshed by Phase 164 (Doxorubicin rename work). However, this is a read-only input for R/112 attribution only. Any rebuild would not affect R/111's DoI encounter classification or the encounter-grain counts that constitute the DOI-REG-03 gate.

---

## Task 3: HiPerGator Runtime Gate (DOI-REG-03)

**Run date:** 2026-10-12
**Host:** c0700a-s28.ufhpc (or equivalent)
**Mode:** PRODUCTION (real DIAGNOSIS table via pcornet.duckdb)
**Elapsed:** ~0.2 minutes (R/4.5 interactive session)
**Unit:** Encounters (R/111 doi_encounters.rds, encounter grain)

### DoI Category Counts — Side-by-Side Comparison

| doi_category | Phase 130 Baseline (2026-07-16) | Today (2026-10-12) | Match? |
|---|---|---|---|
| Hematologic Autoimmune | 10,797 | 10,797 | EXACT |
| SLE / Connective Tissue | 5,816 | 5,816 | EXACT |
| Rheumatoid Arthritis | 5,801 | 5,801 | EXACT |
| Inflammatory Bowel Disease | 4,128 | 4,128 | EXACT |
| Psoriasis | 1,740 | 1,740 | EXACT |
| Inflammatory Myopathy | 1,657 | 1,657 | EXACT |
| Neurological Autoimmune | 1,154 | 1,154 | EXACT |
| Vasculitis | 1,020 | 1,020 | EXACT |
| Pemphigoid | 94 | 94 | EXACT |
| Pemphigus | 42 | 42 | EXACT |
| **Total** | **32,249** | **32,249** | **EXACT** |

**Verdict: Exact match — DuckDB pcornet.duckdb unchanged since 2026-07-16.**

### Clinical Plausibility

- Hematologic Autoimmune dominates (ITP, AIHA, Evans syndrome) — consistent with OneFlorida+ hematology-heavy case mix
- RA + SLE/CT together account for 11,617 encounters — dominant autoimmune indication base for rituximab/MTX
- NMO/Pemphigus rare (42-94 encounters) — expected for these uncommon conditions
- Plausibility: PASS

### Mutual Exclusivity

0 codes classify as BOTH DoI and cancer. Hard-stop assertion (`sum(is_doi_code(DX) & is_cancer_code(DX)) == 0`) passed.

### Patient Counts

- Patients with any DoI: 1,581
- Patients with any DoI who are in the HL cohort: 1,572

### R/88 Result

**ALL 920 CHECKS PASSED.**

Section 15w PASS block confirmed in output. SMOKE-130-01 footer confirmed in validated requirements list.

### R/112 Output (doi_attribution_report.xlsx)

Four sheets produced and confirmed:
1. Patient Prevalence
2. Encounter Co-occurrence
3. Drug x DoI Summary
4. Metadata

---

## Deviations from Plan

### Unrelated Fix — Non-Blocking

**[Rule 1 - Bug] R/88 IMMU fix (commit bd94062) — stale is_sct_conditioning_context filter**

- **Found during:** Pre-run R/88 review
- **Issue:** R/88 line 1578 referenced `is_sct_conditioning_context`, a column removed in Phase 99 (data.table infrastructure migration). Checks 13-15 used this stale filter, causing incorrect IS_LOCAL-gated assertions.
- **Fix:** Replaced with absence-based checks (checking that forbidden columns are absent rather than filtering on a column that no longer exists).
- **Files modified:** R/88_smoke_test_comprehensive.R
- **Commit:** bd94062
- **Impact on DOI-REG-03:** None — this fix is in the IMMU section of R/88, unrelated to Section 15w (DoI layer). The 920-check pass total accounts for this replacement (checks replaced, not added or removed).

---

## Self-Check: PASSED

- 173-01-SUMMARY.md written with evidence table and side-by-side count comparison
- DOI-REG-01/02/03 marked [x] in REQUIREMENTS.md
- ROADMAP.md Phase 173 marked complete
- STATE.md updated
- All committed
- `grep -c "DOI-REG-.*pending" .planning/REQUIREMENTS.md` returns 0
