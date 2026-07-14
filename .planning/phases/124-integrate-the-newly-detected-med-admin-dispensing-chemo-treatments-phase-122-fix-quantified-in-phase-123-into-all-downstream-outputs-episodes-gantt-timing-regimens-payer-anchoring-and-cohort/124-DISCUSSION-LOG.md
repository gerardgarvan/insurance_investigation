# Phase 124: Integrate MED_ADMIN/DISPENSING Chemo Into Downstream Outputs - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-14
**Phase:** 124-integrate-the-newly-detected-med-admin-dispensing-chemo-treatments
**Areas discussed:** Validation deliverable, Gantt/new-record labeling, Regimen-label changes, Output scope, Drug-name normalization (user-added)

---

## Area selection

| Option | Selected |
|--------|----------|
| Validation deliverable | ✓ |
| Gantt/label for new records | ✓ |
| Regimen-label changes | ✓ |
| Output scope | ✓ |

**User's choice:** All four areas.

---

## Validation deliverable

| Option | Description | Selected |
|--------|-------------|----------|
| Regenerate + before/after report | Regenerate + output-level before/after comparison (Amy-ready) | ✓ |
| Regenerate + smoke validation only | Regenerate + R/88 smoke + row-count assertions, no diff artifact | |
| Regenerate only | Re-run only; rely on Phase 123 source-level numbers | |

**User's choice:** Regenerate + before/after report (D-01, D-02).

| Baseline option | Description | Selected |
|-----------------|-------------|----------|
| Snapshot current outputs first | Snapshot pre-fix outputs, then regenerate and diff | |
| Use existing cached snapshots | Reuse Phase-16 `.rds` snapshots if they predate the fix | |
| You decide | Claude's discretion | ✓ |

**User's choice:** You decide (D-03).

---

## Gantt / new-record labeling

| Code Type option | Description | Selected |
|------------------|-------------|----------|
| True source code type | `NDC` for DISPENSING/MED_ADMIN-ND, `RXNORM` for MED_ADMIN-RX | ✓ |
| Normalize to RXNORM | All labeled RXNORM with resolved CUI | |
| You decide | Researcher picks | |

**User's choice:** True source code type (D-04).

| Source+Name option | Description | Selected |
|--------------------|-------------|----------|
| New source values + best-available name | DISPENSING/MED_ADMIN values; name = crosswalk → RAW_MEDADMIN_MED_NAME → blank | ✓ |
| New source values + crosswalk name only | DISPENSING/MED_ADMIN values; crosswalk names only, else blank | |
| You decide | Researcher picks | |

**User's choice:** Initially asked for clarification on 1 vs 2; after explanation chose **Best-available fallback** (D-05, D-06). Names always normalized via `canonicalize_drug_name()`.

---

## Regimen-label changes

| Option | Description | Selected |
|--------|-------------|----------|
| Regenerate + flag changes | Regenerate + per-patient before→after regimen-shift report | |
| Regenerate silently | Regenerate; new distribution stands on its own | ✓ |
| You decide | Researcher picks granularity | |

**User's choice:** Regenerate silently (D-09) — aggregate distribution goes in the D-02 report.

| Regimen input option | Description | Selected |
|----------------------|-------------|----------|
| Treat all sources equally | DISPENSING/MED_ADMIN dates feed regimen labeling like PRESCRIBING | ✓ |
| Flag source in regimen review | Carry contributing source into a change report | |
| You decide | Researcher decides | |

**User's choice:** Treat all sources equally (D-10-reg).

---

## Output scope

| Option | Description | Selected |
|--------|-------------|----------|
| Core treatment products | Episodes, timing, regimens, Gantt, payer, cohort flags, coverage, inventory | ✓ |
| Full suite incl. viz + PPTX | Above + waterfall/Sankey + PPTX | |
| You decide | Researcher maps dependency graph | |

**User's choice:** Core treatment products (D-10, D-11).

| Tableau/grouping option | Description | Selected |
|-------------------------|-------------|----------|
| Include them | Regenerate TABLE-1/2 (R/36) + drug-grouping (R/56/R/57) | ✓ |
| Exclude — core only | Separate refresh | |
| You decide | Researcher checks routing | |

**User's choice:** Include them (D-10).

---

## Drug-name normalization (user-added requirement)

**User's free-text (readiness prompt):** "I want all drugs to be normalized to same spellings despite source for final gantt datas."

**Follow-up clarifications (plain text):**
- Scope: "Normalize all regenerated outputs" — not just Gantt (D-07).
- Unmapped names: "surface an audit list of unmapped names then we can see if they can fit in[to] the generated outputs" — keep cleaned raw string in output + dedicated audit list for later alias extension (D-08).

**Captured as:** D-07 (single canonical spelling across ALL regenerated outputs, no raw strings leak) and D-08 (unmapped-name audit list, Phase 114-style).

---

## Claude's Discretion

- Baseline-capture mechanism for the before/after report (D-03)
- DuckDB re-run orchestration + HiPerGator runtime checkpoint
- Report sheet layout/styling, script number/registration, R/88 smoke sections
- Location of the unmapped-name audit list (standalone xlsx vs sheet in report)

## Deferred Ideas

- Immunotherapy MED_ADMIN/DISPENSING contribution
- Correcting `chemo_rxnorm` (Phase 123 D-10's 5 candidates)
- PPTX / waterfall / Sankey regeneration
- Extending drug-name aliases from the D-08 audit
- Broader audit of other tables for code-column mismatches
