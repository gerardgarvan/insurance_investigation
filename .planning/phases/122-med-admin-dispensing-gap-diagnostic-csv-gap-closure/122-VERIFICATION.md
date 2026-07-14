---
status: passed
phase: 122-med-admin-dispensing-gap-diagnostic-csv-gap-closure
verified: 2026-07-14
method: structural (local) + runtime confirmation (HiPerGator)
---

# Phase 122 Verification — MED_ADMIN/DISPENSING Chemo-Detection Gap Closure

**Status: PASSED** — goal achieved and confirmed with production runtime evidence.

## Goal

Fix the RXNORM_CUI-column mismatch so DISPENSING and MED_ADMIN contribute chemo
treatment detection across all 7 consumers, including an NDC→RxNorm crosswalk;
correct the fixtures/col-specs that masked the bug.

## Runtime evidence (HiPerGator, 2026-07-14)

Source logs: `output/logs/phase122_verification_20260714_132148.log`,
`output/logs/phase122_recheck_20260714_133655.log`.

### MED_ADMIN RX-typed path (D-01) — PROVEN
R/107 diagnostic, cohort-scoped (9,282 HL patients):
- PRESCRIBING baseline: 817 patients / 5,265 (ID,date) pairs
- MED_ADMIN RX-typed chemo match: 1,670 patients / 14,041 (ID,date) pairs / 33,092 rows
- **Increment beyond PRESCRIBING: +1,139 patients / +10,752 chemo dates; 68 patients gain an earlier first-chemo date**
- The drug-order chemo pathway roughly doubles (817 → ~1,956 patients).

### NDC→RxNorm crosswalk path (D-02) — PROVEN
`data/reference/ndc_rxnorm_crosswalk.rds` (built by R/108 on HiPerGator, committed):
- 24,327 distinct NDCs queried → 16,588 resolved to an RxCUI (7,739 miss)
- **126 NDCs map to a chemo RxCUI, covering 42 of 97 chemo ingredients**
- Unlocks DISPENSING (4,386 patients / 719K rows) + MED_ADMIN-ND (2,720 patients / 523K rows), previously zero.

### Smoke test
- R/88 Section 15t: **14/14 PASS** (after the Check-8 false-positive fix — RAW_RXNORM_CUI was matching the bare-column grep).
- R/88 overall: **1/668** — the single remaining FAIL is `R/102 DEATH_CAUSE field-availability guard`, a **pre-existing Phase 118/119 issue unrelated to this phase**.

## Must-haves (D-01..D-07)

| Decision | Status | Evidence |
|----------|--------|----------|
| D-01 MED_ADMIN RX-typed fix | ✅ | R/107 +1,139 patients; §15t Check for MEDADMIN_TYPE=="RX" |
| D-02 NDC crosswalk | ✅ | crosswalk built; 126 chemo NDCs / 42 ingredients |
| D-03 D-12 revision | ✅ | R/01 comments revised; §15t Check 9 PASS |
| D-04 ID not PATID | ✅ | helper + consumers use ID |
| D-05 graceful degradation | ✅ | load_ndc_crosswalk returns character(0) when absent |
| D-06 all 7 consumers | ✅ | §15t Checks 10-13; R/10/11/26/25/27/20/76 patched |
| D-07 fixtures corrected | ✅ | §15t Checks 1-2 (no phantom RXNORM_CUI / RAW_DISPENSE_MED_NAME) |

## Residual / follow-up (not blocking)

- **R/102 DEATH_CAUSE field-availability guard FAIL** — pre-existing (Phase 118/119); the check likely went stale when R/102 was rewritten to read the DEATH_CAUSE table. Track separately.
- Downstream regeneration (episodes/Gantt/timing/payer outputs) now benefits from the expanded sources — a separate regeneration pass, per the phase's deferred scope.
- Immunotherapy MED_ADMIN/DISPENSING detection intentionally left untouched (chemo-only scope; R/26 immuno guards preserved).
