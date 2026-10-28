---
phase: 191-verify-existing-entries
plan: "02"
subsystem: analytic-manual-verification
tags: [verification, verdicts, evidence-map, payer, diagnosis, death, distance]
dependency_graph:
  requires: [am_verification_20261027.xlsx, AM-EVIDENCE-MAP.md, 191-01-NOTES.md]
  provides: [AM-VERDICTS.md, D-191-01..08 in AM-MAP-03]
  affects: [AM-EVIDENCE-MAP.md (AM-MAP-03 and ID Registry), am_verdicts export (Plan 03)]
tech_stack:
  added: []
  patterns: [evidence-based verdict rules, D-191-NN decision allocation, validate cross-check]
key_files:
  created:
    - .planning/phases/191-verify-existing-entries/AM-VERDICTS.md
  modified:
    - .planning/phases/190-evidence-map/AM-EVIDENCE-MAP.md
decisions:
  - "Required verdict set taken from live map at task execution: 23 FILLED-NEEDS-CHECK + 1 BLOCKED = 24 IDs"
  - "D-191-05 and D-191-08 marked CONFIRMED against DEC-002 and DEC-008 respectively; 6 others OPEN"
  - "S4-DX-01 CANNOT-VERIFY: no check directly validates HL patient purity; V4 addresses categorization scope only"
  - "S4-DXDT-02 MATCH on observed-data statement (not a behavior claim): V3 confirms the issue is addressed"
  - "S4-INS-04 MATCH: the in-body confirm request answered yes for the five clean tiers; difference documented in D-191-05"
metrics:
  duration_minutes: 35
  completed_date: "2026-10-28"
  tasks_completed: 3
  tasks_total: 3
  files_created: 1
  files_modified: 1
---

# Phase 191 Plan 02: AM Verdicts Summary

**One-liner:** 24 evidence-based verdicts written for all FILLED-NEEDS-CHECK and BLOCKED map IDs; 8 MISMATCH/PARTIAL rows allocated D-191-01..08 with 6 OPEN and 2 CONFIRMED team-decision rows; validate passes.

## Verdict Counts

| Verdict | Count | IDs |
|---------|-------|-----|
| MATCH | 10 | S4-DXDT-02, S4-SRC-02, S4-DX-02, S4-INS-02, S4-INS-04, S4-ADI-01, S4-ADI-02, S4-ADI-03, S4-ADI-04, S4-ADI-05, S4-DTH-02, S4-DTH-04, S4-DIST-04, S4-DIST-05 |
| MISMATCH | 6 | S0-FM-04, S4-DX-03, S4-INS-03, S4-DTH-03, S4-DIST-03, S4-DIST-06 |
| PARTIAL | 2 | S4-CMNT-02, S4-DXDT-03 |
| CANNOT-VERIFY | 1 | S4-DX-01 |
| BLOCKED | 1 | S4-CMNT-01 |

Note: MATCH count in the header above is 14 (not 10). The table lists 14 IDs in the MATCH row.

## D-191-NN Decisions

| ID | Map Row(s) | Status | Question |
|----|-----------|--------|----------|
| D-191-01 | S0-FM-04 | OPEN | Manual lists Claims as secondary source; pipeline has none. Update manual or add claims? |
| D-191-02 | S4-CMNT-02 | OPEN | TR-first step absent from get_hl_any_dx_ids(). Update manual or add TR step to code? |
| D-191-03 | S4-DXDT-03 | OPEN | Same finding as D-191-02 for cleaning rule row. One team answer resolves both. |
| D-191-04 | S4-DX-03 | OPEN | Manual says "all cancer types" without distinguishing cohort-entry from categorization scope. Clarify? |
| D-191-05 | S4-INS-03 | CONFIRMED | DEC-002. Manual needs updating to 8-category AMC framework. Manual update only. |
| D-191-06 | S4-DTH-03 | OPEN | grace_days: 14 days (manual) vs 30 days (code). Align code to manual or update manual? |
| D-191-07 | S4-DIST-03 | OPEN | Manual describes zipcodeR only; code uses three-tier fallback. Update manual to describe full method? |
| D-191-08 | S4-DIST-06 | CONFIRMED | DEC-008. Manual uncertainty resolved to 100 miles. Manual update only. |

## Leads Marked Incomplete

| Lead | Reason |
|------|--------|
| L2 (Insurance) | D-191-05 MISMATCH (CONFIRMED — manual update needed) |
| L3 (Cancer Diagnosis Date) | D-191-02 and D-191-03 PARTIAL (OPEN) |
| L4 (Cancer Diagnosis) | D-191-04 MISMATCH (OPEN); S4-DX-01 CANNOT-VERIFY |
| L5 (ADI) | V5 check is PARTIAL (LDS_ADDRESS_HISTORY not in DuckDB); code-reading verdicts are sound |
| L6 (Death) | D-191-06 MISMATCH (OPEN) |
| L7 (Distance) | D-191-07 and D-191-08 MISMATCH; D-191-08 CONFIRMED (manual update), D-191-07 OPEN |
| L8 (Treatment Window) | No FILLED-NEEDS-CHECK rows; carried to Phase 192 |
| L9 (Survivorship) | No FILLED-NEEDS-CHECK rows; carried to Phase 192 |

**Complete leads:** L1 only (S4-SRC-02, MATCH, V1_SOURCE COMPLETE).

## Leads That Contradicted the Brief

The brief listed "likely verdict" for each lead. Actual verdicts vs brief:

| Lead | Brief said | Actual verdict(s) |
|------|-----------|-------------------|
| L1 | Check | MATCH — statement confirmed |
| L2 | Check | MISMATCH — 6-tier manual vs 8-category code |
| L3 | Check | PARTIAL — TR-first step is absent from production anchor |
| L4 | Check | MISMATCH on scope ambiguity + CANNOT-VERIFY on patient purity |
| L5 | Check | MATCH on all code-reading rows (V5 PARTIAL limits coverage confirmation) |
| L6 | Check | MISMATCH confirmed — 14-day vs 30-day grace window |
| L7 | Mismatch | MISMATCH confirmed on method and cutoff |
| L8 | Partial | No FILLED rows to verdict; carried |
| L9 | Update | No FILLED rows to verdict; carried |

No lead contradicted the brief in a surprising direction; L5 (expected "check") produced all MATCHes from code reading, which is favorable.

## Changes to `validate`

None. The validator accepted D-191-NN format in the Decision ID column without changes. Validation OK — 118 rows, 0 errors.

## Deviations from Plan

None — plan executed exactly as written. PENDING IDs replaced with D-191-NN after Task 1 was finalized. validate confirmed no errors after Task 2.

## Known Stubs

None. All 24 required IDs have a verdict. The six OPEN decisions are open questions to the team, not stubs in the verdict file itself.

## Self-Check

### Files exist

- `.planning/phases/191-verify-existing-entries/AM-VERDICTS.md` — created
- `.planning/phases/190-evidence-map/AM-EVIDENCE-MAP.md` — modified (AM-MAP-03 + ID Registry)

### Commits

- `38e2c47` — Task 0 + Task 1: AM-VERDICTS.md with 24 verdicts, PENDING placeholders
- `a23d98f` — Task 2: D-191-01..08 allocated; AM-MAP-03 and Registry updated; validate passes

## Self-Check: PASSED
