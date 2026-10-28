# Phase 191: Verify Existing Entries - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-27
**Phase:** 191-verify-existing-entries
**Areas discussed:** Script scope (queries vs code-reading), Workbook sheet design, D-191-NN decision log location, c0 BLOCKED handling

---

## Script scope: queries vs code-reading

| Option | Description | Selected |
|--------|-------------|----------|
| Pre-filled stub rows in the script | Script writes stub rows with hard-coded citations for L7/L8/L9 | |
| Script covers query leads only; hand-fill the rest | Script runs queries for L1–L6; L7/L8/L9 added by hand to workbook | |
| Custom (user-specified) | AM-VERDICTS.md as authoritative verdict file; R script = query runner only; verdicts-export merges both | ✓ |

**User's choice:** R script runs query checks only (L1–L4, L6, V5_ZIPCOVER side of L5) and writes results, not verdicts. All verdicts — including L5 method, L7, L8, L9, and every FILLED-NEEDS-CHECK row — go in `AM-VERDICTS.md` in the phase folder. A new `verdicts-export` subcommand in `tools/am_evidence/am_evidence_map.py` merges AM-VERDICTS.md with AM-EVIDENCE-MAP.md into the verdict workbook and fails if any FILLED-NEEDS-CHECK or BLOCKED map ID lacks exactly one verdict row. No verdicts hard-coded in R; nothing hand-typed into Excel.

---

## Workbook sheet design

| Option | Description | Selected |
|--------|-------------|----------|
| One sheet per lead (9 sheets: L1–L9) | Each lead gets its own sheet | |
| One sheet per query run | Each SQL/DuckDB query gets its own sheet (check ID granularity) | |
| Custom (user-specified) | Sheet names = check IDs matching AM-VERDICTS.md citations | ✓ |

**User's choice:** Sheet names = check IDs: `V1_SOURCE`, `V2_INSURANCE`, `V3_DXDATE`, `V4_DXSCOPE`, `V5_ZIPCOVER`, `V6_DEATH` (add `V2b_...` only if a lead truly needs a second query). Sheet order: KEY (leftmost), V-sheets, QC, Gaps. Each sheet starts with a header block: check ID, lead, map ID(s), query purpose, run date. No sheets for code-reading-only leads. Counts 1–10 suppressed; ID-level detail goes to `output/internal/` RDS.

---

## D-191-NN decision log location

| Option | Description | Selected |
|--------|-------------|----------|
| STATE.md open-decisions table | Append to existing STATE.md decisions table | |
| AM-VERDICTS.md inline | MISMATCH rows carry D-ID assigned inline | |
| Custom (user-specified) | AM-MAP-03 table in AM-EVIDENCE-MAP.md; STATE.md gets one-line pointer | ✓ |

**User's choice:** Add D-191-NN rows to the AM-MAP-03 Team Decisions table in AM-EVIDENCE-MAP.md (same columns and statuses as D-190-01: Status OPEN, Raised By "Phase 191 verification", Map Row(s) linked). Each MISMATCH row in AM-VERDICTS.md carries its D-191-NN in a Decision ID column. `verdicts-export` checks every MISMATCH has one and that the ID exists in the decisions table. Register each new ID in the ID Registry. STATE.md gets a one-line pointer only.

---

## c0 BLOCKED handling

| Option | Description | Selected |
|--------|-------------|----------|
| AM-VERDICTS.md row with verdict = BLOCKED; no workbook sheet | BLOCKED row citing D-190-01 OPEN; verdict workbook has BLOCKED status | |
| Skip c0 entirely in Phase 191 | verdicts-export skips BLOCKED items in completeness check | |
| Custom (user-specified) | Add BLOCKED to valid verdicts; verdicts-export requires row for BLOCKED map IDs; Gaps sheet in workbook | ✓ |

**User's choice:** Add `BLOCKED` to the valid verdict values. `verdicts-export` requires exactly one verdict row for every FILLED-NEEDS-CHECK and BLOCKED map ID (c0 = `S4-CMNT-01`). c0 also listed on a Gaps sheet in the verdict workbook. This closes AM-VER-02 for c0 as "c0 recorded as blocked."

---

## Claude's Discretion

- Script number assignment for `R/NNN_am_verification.R`
- Exact column order within AM-VERDICTS.md rows
- Whether to use Python script or manual entry to write D-191-NN rows into AM-EVIDENCE-MAP.md

## Deferred Ideas

None.
