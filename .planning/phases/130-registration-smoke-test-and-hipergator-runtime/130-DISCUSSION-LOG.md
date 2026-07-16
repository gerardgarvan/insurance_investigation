# Phase 130: Registration, Smoke Test, and HiPerGator Runtime - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-16
**Phase:** 130-registration-smoke-test-and-hipergator-runtime
**Areas discussed:** HiPerGator runtime gate, R/88 smoke-test scope, R/39 + SCRIPT_INDEX registration, Fixture-based local confidence

---

## Area Selection

All four presented gray areas were selected for discussion.

| Area | Selected |
|------|----------|
| HiPerGator runtime gate | ✓ |
| R/88 smoke-test scope | ✓ |
| R/39 + SCRIPT_INDEX registration | ✓ |
| Fixture-based local confidence | ✓ |

---

## HiPerGator Runtime Gate

| Option | Description | Selected |
|--------|-------------|----------|
| Human-verify checkpoint | Structural code verified on Windows; real-data runtime becomes a HUMAN-UAT item; user runs on cluster and pastes logged DoI counts into transition notes | ✓ |
| Hard block until log | Phase stays incomplete until the cluster runtime log is provided | |
| Split into follow-up | Structural code lands and phase closes; runtime tracked as a standalone follow-up todo | |

**User's choice:** Human-verify checkpoint
**Notes:** Resolves the PROJECT.md "Dual-environment verification … ⚠️ Revisit (prose-only)" flag with a real log. Logged counts (RA dominant; NMO/pemphigus rare) recorded verbatim in transition/completion notes → D-01, D-01a.

---

## R/88 Smoke-Test Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Structural + gated runtime | Local grep/parse checks + IS_LOCAL-gated real-data block; validates both R/111 .rds and R/112 xlsx; section 15w | (adopted, checks delegated) |
| Structural-only | No runtime block in R/88; runtime handled separately via R/39 on cluster | |
| You decide checks | Lock 15w + runtime block; planner finalizes exact check list mirroring 15v | ✓ |

**User's choice:** You decide checks
**Notes:** Section slot 15w and the IS_LOCAL-gated runtime block are locked (D-02); both grains validated incl. mutual-exclusivity hard-stop (D-03); exact final check list delegated to planner mirroring Section 15v (D-03a).

---

## R/39 + SCRIPT_INDEX Registration

| Option | Description | Selected |
|--------|-------------|----------|
| Both, dependency order | R/111 then R/112 in investigation_scripts; only doi_attribution_report.xlsx in expected_xlsx; two SCRIPT_INDEX rows | ✓ |
| R/112 only in loop | Register only R/112; R/111 treated as upstream prerequisite | |
| You decide placement | Register both; planner chooses vector position/wording | |

**User's choice:** Both, dependency order
**Notes:** Corrects the roadmap single-script naming slip → D-04, D-05, D-06.

---

## Fixture-Based Local Confidence

| Option | Description | Selected |
|--------|-------------|----------|
| Schema + non-empty | Assert schema-valid, non-empty output + three-state flag present locally; exact counts reserved for HiPerGator log | ✓ |
| Regression-grade counts | Assert specific expected DoI hit counts against Phase-127 fixtures locally | |
| You decide | Planner chooses assertion strength from existing fixture sections | |

**User's choice:** Schema + non-empty
**Notes:** Robust to fixture edits; real-data counts carry the clinical meaning → D-07.

---

## Claude's Discretion

- Exact final R/88 15w check list and wording (mirror 15v).
- `investigation_scripts` vector position + comment wording (R/111 before R/112).
- SCRIPT_INDEX row prose (roles correct).
- Whether the runtime HUMAN-UAT runs via R/88 alone or R/39 end-to-end on the cluster.

## Deferred Ideas

- Roadmap prose cleanup of stale "[30/30]" and "R/111_doi_attribution_report.R" wording — governed by CONTEXT decisions, prose left as-is.
- Externally-shareable suppressed workbook — deferred from Phase 129.
