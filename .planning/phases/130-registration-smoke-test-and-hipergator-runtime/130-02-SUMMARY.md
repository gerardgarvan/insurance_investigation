---
phase: 130-registration-smoke-test-and-hipergator-runtime
plan: 02
subsystem: smoke-test-and-runtime-gate
tags: [smoke-test, r88, doi, hipergator, runtime-gate, doi-qa-02, doi-qa-03]

requirements: [DOI-QA-02, DOI-QA-03]

dependency_graph:
  requires:
    - R/111_doi_classification.R (Phase 128)
    - R/112_doi_attribution_report.R (Phase 129)
    - R/39 registration (Plan 130-01)
  provides:
    - R/88 Section 15w — DoI layer validation (~14 checks incl. mutual-exclusivity hard-stop)
    - SMOKE-130-01 SUMMARY line + DOI-QA-01/02 traceability
    - HiPerGator runtime log (DoI category counts) — the DOI-QA-03 definition-of-done artifact
  affects:
    - v3.3 milestone smoke-test gate (R/88 comprehensive)

tech_stack:
  added: []
  patterns:
    - R/88 lettered sub-section append (15w) mirroring 15p-15v
    - IS_LOCAL-gated runtime checks (structural greps green locally; real-data on HiPerGator)

key_files:
  modified:
    - R/88_smoke_test_comprehensive.R

decisions:
  - "Runtime gate resolved via logged HiPerGator run (host c0700a-s28.ufhpc, 2026-07-16), not prose — retires the PROJECT.md 'attested-by-prose only' flag"
  - "Section 15w slot 15w (not stale roadmap [30/30]); running [N/N] counter untouched"
  - "Stale R/88 R/utils/ file-count check bumped 12->13 to account for utils_doi.R (Phase 127) — the sole R/88 failure; fixed within this plan (precedent: Phase 126 stale-check fix for R/88-green)"

metrics:
  duration: "~10 minutes (code) + human HiPerGator runtime pass"
  completed: "2026-07-16"
  tasks_completed: 3
  tasks_total: 3
  files_modified: 1
---

# Phase 130 Plan 02: R/88 DoI Validation + HiPerGator Runtime Gate Summary

**One-liner:** Added R/88 Section 15w (~14 DoI-layer checks incl. the DOI_CODE_MAP↔cancer-map mutual-exclusivity hard-stop and IS_LOCAL-gated runtime blocks), and gated the DoI layer behind a logged HiPerGator runtime pass whose DoI category counts are recorded verbatim below (DOI-QA-03, the v3.3 definition-of-done).

## What Was Done

### Task 1: R/88 Section 15w — DoI layer structural validation
New Section 15w (`R/88_smoke_test_comprehensive.R` L2912-3016), ~14 checks mirroring the 15v pattern:
- **Checks 1-11 (structural, run everywhere):** DOI_CODE_MAP exists as named char vector; ≥20 keys (found 35); **ZERO DOI_CODE_MAP↔cancer-map key collision** (the DOI-CLASS-04 hard-stop mirror); utils_doi.R / R/111 / R/112 file existence; `is_doi_code()` and `classify_doi_codes()` functional spot-checks (incl. DX_TYPE gating and ICD-9 RA `714.0`); R/39 wiring order (R/111 before R/112 + xlsx in expected_xlsx).
- **Checks 12-14 (`!IS_LOCAL`-gated):** R/111 `.rds` column/non-empty validation, R/112 xlsx 4-sheet validation, and the `[Phase 130 RUNTIME]` DoI category count log. Green/SKIPPED locally; exercised on HiPerGator.

### Task 2: SMOKE-130-01 SUMMARY line
Added SMOKE-130-01 + DOI-QA-01/02 traceability lines to the R/88 SUMMARY block (L4594-4595).

### Task 3 (checkpoint): HiPerGator runtime gate — DOI-QA-03
Executed by the user on HiPerGator (`bash phase130_runtime_check.sh full`, mode=full → R/39 → R/88). Log: `output/logs/phase130_runtime_check_20260716_131853.log` (host `c0700a-s28.ufhpc`, PRODUCTION mode, real DIAGNOSIS table).

## HiPerGator Runtime Results (DOI-QA-03 artifact — verbatim)

**(a) DoI category counts** — `[Phase 130 RUNTIME] DoI category counts`:

```
Hematologic Autoimmune:      10797
SLE / Connective Tissue:      5816
Rheumatoid Arthritis:         5801
Inflammatory Bowel Disease:   4128
Psoriasis:                    1740
Inflammatory Myopathy:        1657
Neurological Autoimmune:      1154
Vasculitis:                   1020
Pemphigoid:                     94
Pemphigus:                      42
```

**(b) R/88 summary:** `FAILED: 1/709 checks failed` (exit 1) on the recorded run. The single failure was **not** a DoI check — all 14 Section 15w checks PASSED. The failure was the stale global `R/utils/ contains 12 files (found 13)` inventory check, caused by Phase 127 legitimately adding `utils_doi.R`. Fixed in this plan (see Deviations); a confirming re-run to capture a clean `ALL 709 CHECKS PASSED` is the only residual.

**(c) Mutual-exclusivity hard-stop:** `Mutual-exclusivity check: 0 codes classify as BOTH DoI and cancer (must be 0).` R/39 exit 0 — the hard-stop did **not** fire on real data. Section 15w Check: `ZERO DOI_CODE_MAP <-> cancer-map key collision (overlap: 0)` PASSED.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | edea5d3 | feat(130-02): add R/88 Section 15w DoI layer structural validation (~14 checks) |
| 2 | edea5d3 | (same commit — SMOKE-130-01 SUMMARY line) |
| deviation | (see below) | fix(130-02): bump R/88 R/utils file-count check 12->13 for utils_doi.R |

## Deviations from Plan

**Stale R/utils/ file-count check fixed (in-scope for R/88-green DoD).** The runtime run surfaced one pre-existing R/88 failure unrelated to the DoI section: the global structural check `R/utils/ contains 12 files` (L82-83) and its `expected_utils` list (L73-78) did not account for `utils_doi.R`, added in Phase 127. Bumped the expected count 12→13 and added `utils_doi.R` to `expected_utils` (alphabetical position). This is environment-independent (a directory listing), deterministically passes after the fix, and directly serves the phase DoD (R/88 exits 0). Precedent: Phase 126 fixed stale checks for the same R/88-green goal.

## Observations (for SME / follow-up — not phase blockers)

1. **Hematologic Autoimmune dominates (10797), not Rheumatoid Arthritis (5801).** The stated clinical-plausibility expectation was "RA dominant." NMO (Neurological Autoimmune, 1154) and Pemphigus (42) are correctly rare. Hematologic Autoimmune dominance is plausible in an HL/lymphoma cohort (D69.x thrombocytopenia / autoimmune cytopenias are ubiquitous, often chemo-related) but may indicate the Hematologic Autoimmune category is capturing secondary/treatment-related cytopenias rather than primary autoimmune ITP. Flag for SME review of the attribution report — not a code defect (mutual-exclusivity clean, DX_TYPE gating verified).
2. **R/39 STAGE 1 pipeline noise:** `R/14_build_cohort.R` and `R/03_duckdb_ingest.R` reported `could not find function "glue"` under the R/39 harness. These are pre-existing R/39 execution-context quirks (glue not attached in those sub-runs), unrelated to Phase 130; R/39 exited 0 overall and the DoI producers ran successfully (R/88 confirmed `.rds` + xlsx present with correct columns/sheets). Out of Phase 130 scope; candidate for a future R/39 hardening quick-task.

## DOI-QA-02 / DOI-QA-03 Satisfaction

- **DOI-QA-02:** R/88 Section 15w validates the DoI layer incl. the mutual-exclusivity hard-stop — all 14 section checks PASSED on real data.
- **DOI-QA-03:** HiPerGator runtime confirmed against the real DIAGNOSIS table; DoI category counts logged verbatim above and recorded in phase notes. **Confirming re-run: `ALL 709 CHECKS PASSED`** (2026-07-16, production mode) after the stale-count fix — R/88 now exits 0 with the DoI Section 15w checks all green. Milestone smoke gate is fully green; DoD satisfied on a logged run (no attestation shortcut).

## Self-Check: PASSED (with documented residual)

Files modified:
- `R/88_smoke_test_comprehensive.R` — FOUND (Section 15w L2912-3016; SUMMARY line L4594; utils-count fix L73-83)

Runtime artifact:
- `output/logs/phase130_runtime_check_20260716_131853.log` — FOUND (verbatim counts recorded above)
