# Phase 123: Quantify Fix Impact + Unmatched-NDC Audit - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-14
**Phase:** 123-quantify-how-much-the-med-admin-dispensing-chemo-detection-fix-changes-treatment-outputs-before-after-diff-and-investigate-whether-unmatched-ndcs-are-missing-real-chemo
**Areas discussed:** Before/after baseline, Diff scope & metrics, Unmatched-NDC audit, Deliverable & regen scope

---

## Gray-Area Selection

| Option | Selected |
|--------|----------|
| Before/after baseline | ✓ |
| Diff scope & metrics | ✓ |
| Unmatched-NDC audit | ✓ |
| Deliverable & regen scope | ✓ |

**User's choice:** All four areas.

---

## Before/after baseline

| Option | Description | Selected |
|--------|-------------|----------|
| Extend R/107 diagnostic | Source-level before/after in one cohort-scoped script; no full re-run | ✓ |
| Toggle-flag full re-run | Config switch to disable fix, run pipeline twice, diff output files | |
| Hybrid | Source-level headline + regenerate/diff specific downstream files | |

**User's choice:** Extend R/107 diagnostic.
**Notes:** PRESCRIBING-only = before; + MED_ADMIN-RX + NDC-resolved = after. Fast, deterministic, no plumbing.

---

## Diff scope & metrics

| Option | Description | Selected |
|--------|-------------|----------|
| Patient & date counts | # patients + distinct (ID,date) pairs by source | ✓ |
| First-chemo timing shift | # patients gaining earlier first-chemo date + day distribution | ✓ |
| Per-drug/ingredient delta | Which ingredients gain most from new sources | ✓ |
| Regimen-label impact | Whether new dates change ABVD/BV+AVD/Nivo+AVD labels | ✓ |

**User's choice:** All four.
**Notes:** Regimen-label impact flagged as higher effort — requires running regimen logic, not just source counts. Captured as D-06 with an explicit effort note.

---

## Unmatched-NDC audit

| Option | Description | Selected |
|--------|-------------|----------|
| Drug-name string match | Match unmatched NDCs against chemo ingredient list via name text | ✓ |
| Frequency-ranked review | Top-N unmatched NDCs by patient/row volume | ✓ |
| RxNav re-query | Re-query 7,739 unresolved NDCs against alternate endpoints | ✓ |
| Resolved-non-chemo gap check | Check resolved RxCUIs for chemo ingredients missing from chemo_rxnorm | ✓ |

**User's choice:** All four.
**Notes:** RxNav re-query is network-bound → HiPerGator-only runtime checkpoint (Phase 122 R/108 precedent). Resolved-non-chemo gap check flags chemo_rxnorm list gaps (correction is a follow-up).

---

## Deliverable format

| Option | Description | Selected |
|--------|-------------|----------|
| Multi-sheet xlsx | One styled workbook, sheet per concern, Amy-ready | ✓ |
| CSV tables | Plain per-table CSVs | |
| RMarkdown report | Self-contained HTML narrative + tables | |

**User's choice:** Multi-sheet xlsx.

---

## Regeneration scope

| Option | Description | Selected |
|--------|-------------|----------|
| Quantification only | Diff + audit xlsx and stop; regen is a separate pass | ✓ |
| Also regenerate downstream | Re-run/overwrite Gantt/episodes/timing/regimens | |

**User's choice:** Quantification only.

---

## Claude's Discretion

- Extend R/107 in place vs sibling script
- xlsx sheet layout/ordering + styling helpers
- Where RxNav re-query lands + checkpoint structure
- Least-invasive regimen-label computation on both source sets
- Script number / R/39 vs SCRIPT_INDEX registration + R/88 smoke sections

## Deferred Ideas

- Full downstream regeneration with the fix
- Correcting chemo_rxnorm list based on gap-check findings
- Immunotherapy MED_ADMIN/DISPENSING contribution
- Broader audit of other tables for code-column mismatches
